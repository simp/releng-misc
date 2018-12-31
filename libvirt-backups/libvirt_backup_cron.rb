#!/usr/bin/env ruby
#
require 'fileutils'
require 'syslog/logger'

def vm_exists(name)
  system("virsh dominfo --domain #{name} &> /dev/null")
end

def backupdir_exists(dir, name)
   puts "Directroy #{dir} and #{name}"
   unless  dir.start_with?("/")
    @slog.error "Backup Directory, #{dir} must be an absolute path. libvirt Domain #{name} cannot be backed up."
    return false
  end

  unless Dir.exists?(dir)
    @slog.error "Backup Directory, #{dir} does not exist. libvirt Domain #{name} cannot be backed up."
    return false
  end

  unless Dir.exists?("#{dir}/#{name}")
    begin
      Dir.mkdir "#{dir}/#{name}"
    rescue
      @slog.error "Can not create Backup Directory, #{dir}/#{name}. libvirt Domain #{name} cannot be backed up."
      return false
    end
  end
  return true
end

def validate_entry(entry)
   def_backup_dir="/var/backups"
   def_num_of_backups="3"
   def_quiesce="no"

   num_backups = entry[1]
   num_backups.nil? && num_backups = def_num_of_backups

   backup_dir = entry[2]
   backup_dir.nil? && backup_dir = def_backup_dir

   quiesce = entry[3]
   quiesce.nil? && quiesce = def_quiesce

   case quiesce.downcase
   when "y","yes"
       quiesce ="yes"
    default
       quiesce = "no"
    end
   [num_backups, backup_dir, quiesce]
end

backup_file="/etc/libvirt_backups.conf"

@slog = Syslog::Logger.new 'libvirt_backup_cron'
@slog.info "Starting Libvirt Backups"

unless File.exists?(backup_file)
  @slog.error "File #{backup_file} does not exist.  No libvirt backups were done."
  exit
end

File.open(backup_file, "r") do |f|
  f.each_line do |line|
    if line =~ /^#.*/
      next
    end
    entry = line.chomp.split(',')
    vm_name = entry[0]
    @slog.info "Starting backup for #{vm_name}"
    if  vm_exists(vm_name)
      num_backups, backup_dir, quiesce = validate_entry(entry)
      next unless backupdir_exists(backup_dir, vm_name)
      result = system("/usr/local/bin/libvirt_backup.sh #{backup_dir} #{vm_name}  #{quiesce} #{num_backups}")
      exit_status = $?.exitstatus

      if result
       @slog.info "Completed backup for #{vm_name}"
      else
       @slog.error "Error: There was an error during backup of #{vm_name}. Exit status: #{exit_status}"
      end
    else
      @slog.warn "Warning: No VM named #{vm_name}.  Please check configuration file #{backup_file}"
    end
  end
end
