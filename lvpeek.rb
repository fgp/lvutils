#!/usr/bin/ruby
require 'fileutils'
require 'tmpdir'

LVPEEK_ROOT = "/var/lvpeek"

module OPTS
  OPTIONS = [
    { :id => "mode",
      :enabled => proc { true },
      :default => proc { MODE=:mount }
    },
    { :names => %w{--release},
      :id => "mode",
      :desc => "Release cgroup and delete snapshot",
      :enabled => proc { true },
      :validate => /\A[A-Za-z0-9+_.\/-]+\Z/,
      :handler => proc { |cg| MODE=:cleanup; LVPEEK_CGROUP=cg }
    },
    { :names => %w{-g --volume-group},
      :id => "volume-group",
      :desc => "Physical volume group containing the logical volume to inspect",
      :enabled => proc { MODE == :mount },
      :validate => /\A[A-Za-z0-9+_.-]+\Z/,
      :handler => proc { |vg| VOLUME_GROUP=vg }
    },
    { :names => %w{-l --logical-volume},
      :id => "logical-volume",
      :desc => "Logical volume to inspect",
      :enabled => proc { MODE == :mount },
      :validate => /\A[A-Za-z0-9+_.-]+\Z/,
      :handler => proc { |lv| VOLUME=lv }
    },
    { :names => %w{-s --size},
      :id => "size",
      :desc => "Snapshot size in MiB (2^20 bytes)",
      :enabled => proc { MODE == :mount },
      :validate => /\A[0-9]+\Z/,
      :handler => proc { |s| SNAPSHOT_SIZE=s },
      :default => proc { SNAPSHOT_SIZE=1024 }
    },
    { :names => %w{-t --format},
      :id => "format",
      :desc => "Format of logical volume, required if not autodetected by mount",
      :enabled => proc { MODE == :mount },
      :handler => proc { |f| VOLUME_FORMAT=f },
      :default => proc { VOLUME_FORMAT=nil }
    },
  ]
  
  COMMAND = [ ENV["SHELL"] ]

  def self.parse
    # Build keyword hash for argument parsing  
    keywords = {}
    OPTIONS.each do |opt|
      opt[:names].each { |kw| keywords[kw] = opt } if opt.has_key? :names
    end
    
    # Parse arguments
    ids = {}
    while !ARGV.empty?
      # Stop if next argument doesn't look like a keyword or is --
      break if (ARGV.first == "--") || (ARGV.first !~ /\A-/)
      
      # Get next keyword and decode
      kw = ARGV.shift
      opt = keywords[kw]
      raise "invalid option #{kw}" if opt.nil?
      
      # Read as many parameters as the option required
      args = ARGV.shift(opt[:handler].arity)
      
      # Validate parameters
      valid = case opt[:validate]
        when Regexp then opt[:validate] =~ args.first
        when Proc then opt[:validate].call(*args)
        else true
      end
      raise "Invalid arguments #{args.join('  ')} for option #{kw}" unless valid
      
      # Handle option
      ids[opt[:id]] = true
      opt[:handler].call(*args)
    end
    unless ARGV.empty?
      COMMAND.clear
      COMMAND.push *ARGV
    end

    # Call default handlers for option which weren't specified
    # Note that an option is specified if *some* option with the
    # same id is specified, even if it has different keywords.  
    OPTIONS.each do |opt|
      next if ids.has_key? opt[:id]
      next unless opt[:enabled].call
      next unless opt.has_key? :default
      opt[:default].call
      ids[opt[:id]] = true
    end

    # Complain about missing mandatory options  
    OPTIONS.each do |opt|
      next unless opt[:enabled].call
      raise "Missing mandatory option option #{opt[:id]}" unless ids.has_key? opt[:id]
    end
  end
end

def cmd(cmd, opts = {})
  r = Kernel::system *cmd, opts
  raise "#{args.first} failed" unless r
end

begin
  # Parse command-line options
  OPTS::parse

  # Create new mount namespace
  Kernel.syscall(272, 0x00020000) # unshare(CLONE_NEWNS)

  case OPTS::MODE
    when :mount
      # Create unique snapshot name and determine relative cgroup path
      SNAPSHOT = Time::now.strftime("lvpeek-%Y%m%d-%H%M%S-") + ("%06d" % rand(1000000))
      LVPEEK_CGROUP = "/" + OPTS::VOLUME_GROUP + "/" + OPTS::VOLUME + "/" + SNAPSHOT

      # Create snapshot-specific cgroup in lvpeek hierarchy and assign current task.
      # Once the task and all descendents exit, the release_agent will be invoked
      cmd %W(mount -n -t cgroup -o none,name=lvpeek cgroup #{LVPEEK_ROOT})
      File::write LVPEEK_ROOT + "/release_agent", File.dirname(File.expand_path($PROGRAM_NAME)) + "/lvpeek_release_agent.sh"
      FileUtils.mkdir_p LVPEEK_ROOT + LVPEEK_CGROUP
      File::write LVPEEK_ROOT + LVPEEK_CGROUP + "/cgroup.procs", "0"
      File::write LVPEEK_ROOT + LVPEEK_CGROUP + "/notify_on_release", "1"
      cmd %W(umount -n #{LVPEEK_ROOT})
      
      # Create snapshot
      cmd %W(lvcreate --snapshot /dev/#{OPTS::VOLUME_GROUP}/#{OPTS::VOLUME} --name #{SNAPSHOT} --size #{OPTS::SNAPSHOT_SIZE}M), 1 => "/dev/null"

      # Mount snapshot
      cmd %W(mount -n /dev/#{OPTS::VOLUME_GROUP}/#{SNAPSHOT} #{LVPEEK_ROOT} -o ro) + (OPTS::VOLUME_FORMAT ? %W(-t #{OPTS::VOLUME_FORMAT}) : [])
      
      # Run command
      Dir.chdir LVPEEK_ROOT
      Kernel::exec *OPTS::COMMAND
      
   when :cleanup
     # Determine volume group, volume and snapshot from relative cgroup path
     VOLUME_GROUP, VOLUME, SNAPSHOT = *OPTS::LVPEEK_CGROUP.split(/\//)[1..-1]

     # Remove snapshot-specific cgroup
     cmd %W(mount -n -t cgroup -o none,name=lvpeek cgroup #{LVPEEK_ROOT})
     Dir.rmdir LVPEEK_ROOT + OPTS::LVPEEK_CGROUP
     cmd %W(umount -n #{LVPEEK_ROOT})
     
     # Remove snapshot
     cmd %W(lvremove --force #{VOLUME_GROUP}/#{SNAPSHOT})
  end
rescue Exception => e
  STDERR.puts e.message
  exit 1
end
