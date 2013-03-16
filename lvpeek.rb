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
      :handler => proc { |lv| LOGICAL_VOLUME=lv }
    },
    { :names => %w{-s --size},
      :id => "size",
      :desc => "Snapshot size in MiB (2^20 bytes)",
      :enabled => proc { true },
      :validate => /\A[0-9]+\Z/,
      :handler => proc { |s| SNAPSHOT_SIZE=s },
      :default => proc { SNAPSHOT_SIZE=1024 }
    },
  ]
  
  KEYWORDS = {}
  OPTIONS.each do |opt|
    opt[:names].each { |kw| KEYWORDS[kw] = opt } if opt.has_key? :names
  end
  
  
  ids = {}
  while !ARGV.empty?
    kw = ARGV.shift
    opt = KEYWORDS[kw]
    raise "Unknown option #{kw}" if opt.nil?
    
    args = ARGV.shift(opt[:handler].arity)
    
    valid = case opt[:validate]
      when Regexp then opt[:validate] =~ args.first
      when Proc then opt[:validate].call(*args)
      else true
    end
    raise "Invalid arguments #{args.join('  ')} for option #{kw}" unless valid
    
    ids[opt[:id]] = true
    opt[:handler].call(*args)
  end
  
  OPTIONS.each do |opt|
    next if ids.has_key? opt[:id]
    next unless opt[:enabled].call
    next unless opt.has_key? :default
    opt[:default].call
    ids[opt[:id]] = true
  end
  
  OPTIONS.each do |opt|
    next unless opt[:enabled].call
    raise "Missing mandatory option option #{opt[:id]}" unless ids.has_key? opt[:id]
  end
end

Kernel.syscall(272, 0x00020000) # unshare(CLONE_NEWNS)

case OPTS::MODE
  when :mount
    SNAPSHOT_NAME = Time::now.strftime("lvpeek-%Y%m%d-%H%M%S-") + ("%06d" % rand(1000000))
    LVPEEK_CGROUP = "/" + OPTS::VOLUME_GROUP + "/" + OPTS::LOGICAL_VOLUME + "/" + SNAPSHOT_NAME

    # Create snapshot-specific cgroup in lvpeek hierarchy and assign current task.
    # Once the task and all descendents exit, the release_agent will be invoked
    system(*(%w(mount -n -t cgroup -o none,name=lvpeek cgroup) + [LVPEEK_ROOT]))
    File::write(LVPEEK_ROOT + "/release_agent", File.dirname(File.expand_path($PROGRAM_NAME)) + "/lvpeek_release_agent.sh")
    FileUtils.mkdir_p LVPEEK_ROOT + LVPEEK_CGROUP
    File::write LVPEEK_ROOT + LVPEEK_CGROUP + "/cgroup.procs", "0"
    File::write LVPEEK_ROOT + LVPEEK_CGROUP + "/notify_on_release", "1"
    system(*(%w(umount -n) + [LVPEEK_ROOT]))
    
    # Create snapshot
    system(*%W(lvcreate --snapshot /dev/#{OPTS::VOLUME_GROUP}/#{OPTS::LOGICAL_VOLUME} --name #{SNAPSHOT_NAME} --size #{OPTS::SNAPSHOT_SIZE}M))
    
    system("lvs")
    
 when :cleanup
   VOLUME_GROUP, LOGICAL_VOLUME, SNAPSHOT_NAME = *OPTS::LVPEEK_CGROUP.split(/\//)[1..-1]

   # Remove snapshot-specific cgroup
   system(*(%w(mount -n -t cgroup -o none,name=lvpeek cgroup) + [LVPEEK_ROOT]))
   Dir.rmdir LVPEEK_ROOT + OPTS::LVPEEK_CGROUP
   system(*(%w(umount -n) + [LVPEEK_ROOT]))
   
   # Remove snapshot
   system(*%W(lvremove --force #{VOLUME_GROUP}/#{SNAPSHOT_NAME}))
   
   # Log success
   puts "#{Time.now}: Successfully cleaned up #{SNAPSHOT_NAME}"
end
