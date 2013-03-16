#!/usr/bin/ruby
require 'fileutils'
require 'tmpdir'

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
    LVPEEK_ROOT = Dir.mktmpdir("lvpeek_", "/tmp")
    SNAPSHOT_NAME = File.basename(LVPEEK_ROOT)
    LVPEEK_CGROUP = "/" + OPTS::VOLUME_GROUP + "/" + OPTS::LOGICAL_VOLUME + "/" + SNAPSHOT_NAME
    LVPEEK_HIERARCHY = LVPEEK_ROOT + "/lvpeek"
    LVPEEK_MOUNTPOINT = LVPEEK_ROOT + "/mnt"

    # Create directories
    Dir.mkdir(LVPEEK_HIERARCHY)
    Dir.mkdir(LVPEEK_MOUNTPOINT)

    # Create snapshot-specific cgroup in lvpeek hierarchy and assign current task.
    # Register release_agent, which takes care of removing the cgroup and the snapshot
    # once the snapshot-specific cgroup is empty.
    system(*(%w(mount -n -t cgroup -o none,name=lvpeek cgroup) + [LVPEEK_HIERARCHY]))
    File::write(LVPEEK_HIERARCHY + "/release_agent", File.dirname(File.expand_path($PROGRAM_NAME)) + "/lvpeek_release_agent.sh")
    FileUtils.mkdir_p LVPEEK_HIERARCHY + LVPEEK_CGROUP
    File::write LVPEEK_HIERARCHY + LVPEEK_CGROUP + "/cgroup.procs", "0"
    File::write LVPEEK_HIERARCHY + LVPEEK_CGROUP + "/notify_on_release", "1"
    system(*(%w(umount -n) + [LVPEEK_HIERARCHY])) if defined? LVPEEK_HIERARCHY

 when :cleanup
   VOLUME_GROUP, LOGICAL_VOLUME, SNAPSHOT_NAME = *OPTS::LVPEEK_CGROUP.split(/\//)[1..-1]
   LVPEEK_ROOT = "/tmp/" + SNAPSHOT_NAME

   LVPEEK_MOUNTPOINT = LVPEEK_ROOT + "/mnt"
   LVPEEK_HIERARCHY = LVPEEK_ROOT + "/lvpeek"

   # Remove snapshot-specific cgroup
   system(*(%w(mount -n -t cgroup -o none,name=lvpeek cgroup) + [LVPEEK_HIERARCHY]))
   Dir.rmdir LVPEEK_HIERARCHY + OPTS::LVPEEK_CGROUP
   system(*(%w(umount -n) + [LVPEEK_HIERARCHY])) if defined? LVPEEK_HIERARCHY
   
   # Remove directories
   Dir.rmdir LVPEEK_MOUNTPOINT if File::directory? LVPEEK_MOUNTPOINT
   Dir.rmdir LVPEEK_HIERARCHY if File::directory? LVPEEK_HIERARCHY
   Dir.rmdir LVPEEK_ROOT if File::directory? LVPEEK_ROOT

   # Log success
   puts "#{Time.now}: Successfully cleaned up #{SNAPSHOT_NAME}"
end
