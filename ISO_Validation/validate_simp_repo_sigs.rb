#!/usr/bin/env ruby

# This script is designed to be pointed at a SIMP directory as extracted from
# an ISO or a SIMP tarball.
#
# It looks for a RPM named 'simp-gpgkeys*.rpm' and validates that all RPMs in
# the target directory are signed by a key included in the gpgkeys RPM.
#
# Exit Codes:
# * 0 => No Issues Found
# * 1 => General Error
# * 2 => Invalid RPMs Found
#
# Copyright 2018 Onyx Point, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.
#
require 'tmpdir'
require 'optparse'
require 'ostruct'

USAGE="#{$0} [options] <directory with SIMP RPMs>"

def parse_options
  options = OpenStruct.new
  options.report_type = 'invalid'
  options.quiet = false

  _opts = OptionParser.new do |opts|
    opts.banner = USAGE

    opts.separator ""

    opts.on(
      '-t REPORT_TYPE',
      '--report-type REPORT_TYPE',
      'Output a report of this type. May be one of:',
      '  * invalid (default) => Invalid RPMs',
      '  * valid             => Valid RPMs',
      '  * unused_keys       => GPG keys that do not match any package',
      '  * simp_pkgs         => List SIMP Packages',
      '  * simp_dep_pkgs     => List SIMP Dependency Packages',
      '  * other_pkgs        => List Other Vendor Packages'
    ) do |arg|
      valid_reports = [
        'invalid',
        'valid',
        'unused_keys',
        'simp_pkgs',
        'simp_dep_pkgs',
        'other_pkgs'
      ]

      unless valid_reports.include?(arg)
        $stderr.puts("Error: report-type must be one of:\n  * #{valid_reports.join("\n  * ")}")
        exit 1
      end

      options.report_type = arg.strip
    end

    opts.on(
      '-q', '--quiet',
      'No output, returns 1 if invalid RPMs present, 0 otherwise',
      'All other options are ignored'
    ) do
      options.quiet = true
    end
  end

  begin
    _opts.parse!(ARGV)
  rescue OptionParser::ParseError => e
    puts e
    puts _opts
    exit 1
  end

  tgt_dir = ARGV.first

  unless tgt_dir
    $stderr.puts(USAGE)
    exit 1
  end

  unless File.directory?(tgt_dir)
    $stderr.puts("Could not find directory at #{tgt_dir}")
    $stderr.puts(USAGE)
    exit 1
  end

  options.target_dir = File.absolute_path(tgt_dir)

  return options
end

def extract_gpgkeys(tgt_dir)
  gpgkeys_rpm = File.absolute_path(`find #{tgt_dir} -name "simp-gpgkeys*.rpm"`.lines.first.strip)

  unless File.file?(gpgkeys_rpm)
    $stderr.puts("Could not find simp-gpgkeys RPM at #{tgt_dir}")
    exit 1
  end

  valid_sigs = {}

  Dir.mktmpdir do |dir|
    %x{rpm2cpio #{gpgkeys_rpm} | cpio -id -D #{dir} 2>/dev/null}

    %x{find #{dir} -name "RPM-GPG-KEY*"}.lines.each do |vendor_key|
      key_attrs = %x{gpg2 -q --with-subkey-fingerprints --with-key-data #{vendor_key}}.lines.map(&:strip)

      uid = key_attrs.select{ |x| x.start_with?('uid:') }.first.split(':')[-1]

      key_attrs.select { |x| x.start_with?('pub:') || x.start_with?('sub:') }.each do |entry|
        sig = entry.split(':')[4]

        if sig
          valid_sigs[sig.upcase] = uid
        end
      end
    end
  end

  return valid_sigs
end

def valid_build_host?(to_cmp)
  valid_build_hosts = [
    # SIMP Build Host
    '.*\.simp\.dev$',
    '.*\.simp-project\.net$',
    '.*\.simp-project\.com$',
    # EPEL
    '.*\.fedoraproject\.org$',
    # Puppet
    '.*\.puppetlabs\.net$',
    '\.puppetlabs\.lan$',
    '^mesos-jenkins-',
    # CentOS
    '.*\.centos\.org$',
    # PostgreSQL
    '^koji-centos'
  ]

  valid_build_hosts.each do |pattern|
    return true if to_cmp =~ /#{pattern}/
  end

  return false
end

def process_rpms(tgt_dir, valid_sigs)
  rpm_metadata = {
    :valid    => {},
    :invalid  => {},
    :rpm_type => {
      :simp      => [],
      :simp_deps => [],
      :other     => []
    }
  }

  rpms = (`find #{tgt_dir} -type f -name "*.rpm"`).lines.map{|f| File.absolute_path(f.strip)}

  fieldsep = '|'

  rpms.each do |rpm|
    rpm_info = %x{rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}#{fieldsep}%{SIGPGP:pgpsig} %{SIGGPG:pgpsig}#{fieldsep}%{BUILDHOST}\\n' #{rpm} 2>/dev/null}

    rpm_name, rpm_sig, rpm_buildhost = rpm_info.split('|')

    key_id = nil
    if rpm_sig =~ /Key ID (\S+)/
      key_id = $1.upcase
    end

    if key_id
      if valid_sigs[key_id]
        rpm_metadata[:valid][valid_sigs[key_id]] ||= {
          :key  => key_id,
          :rpms => []
        }

        # We signed it
        uid_match = Regexp.new('.+@simp-project.org')

        # Vendor packages
        uid_vendor = Regexp.new('.+@(fedora|centos)')

        if uid_match.match(valid_sigs[key_id])
          rpm_metadata[:rpm_type][:simp] << rpm_name
        elsif uid_vendor.match(valid_sigs[key_id])
          rpm_metadata[:rpm_type][:other] << rpm_name
        else
          rpm_metadata[:rpm_type][:simp_deps] << rpm_name
        end
      else
        rpm_metadata[:invalid][rpm_name] ||= []
        rpm_metadata[:invalid][rpm_name] << "Unknown Key => #{key_id}"
      end
    else
      rpm_metadata[:invalid][rpm_name] ||= []
      rpm_metadata[:invalid][rpm_name] << 'Not Signed'
    end

    unless valid_build_host?(rpm_buildhost)
      rpm_metadata[:invalid][rpm_name] ||= []
      rpm_metadata[:invalid][rpm_name] << "Invalid Build Host: #{rpm_buildhost}"
    end

    unless rpm_metadata[:invalid][rpm_name]
      rpm_metadata[:valid][valid_sigs[key_id]][:rpms] << rpm_name
    end
  end

  return rpm_metadata
end

options = parse_options

valid_sigs = extract_gpgkeys(options.target_dir)
rpm_metadata = process_rpms(options.target_dir, valid_sigs)

if options.quiet
  if rpm_metadata[:invalid].empty?
    exit 0
  else
    exit 1
  end
end

if options.report_type == 'valid'
  rpm_metadata[:valid].each do |k,v|
    puts %{* #{k} #{v[:key]}\n\n  - #{v[:rpms].join("\n  - ")}}
    puts "\n"
  end
end

if options.report_type == 'invalid'
  if rpm_metadata[:invalid].empty?
    puts 'No invalid RPMs found!'
  else
    puts 'Invalid RPMs:'

    rpm_metadata[:invalid].each do |k,v|
      puts "* #{k}:"
      puts %(  * #{Array(v).join("\n  * ")})
    end

    exit 2
  end
end

if options.report_type == 'unused_keys'
  used_sigs = []

  rpm_metadata[:valid].each do |k,v|
    used_sigs << valid_sigs.select do |sig_k, sig_v|
      sig_v == k
    end.map(&:first)
  end

  used_sigs = used_sigs.flatten.uniq

  unused_sigs = (valid_sigs.keys - used_sigs)

  if unused_sigs.empty?
    puts 'All Keys Used'
  else
    puts 'Unused Keys:'

    unused_sigs.each do |sig|
      puts "  * #{sig} => #{valid_sigs[sig]}"
    end
  end
end

if options.report_type == 'simp_pkgs'
  puts rpm_metadata[:rpm_type][:simp].join("\n")
end

if options.report_type == 'simp_dep_pkgs'
  puts rpm_metadata[:rpm_type][:simp_deps].join("\n")
end

if options.report_type == 'other_pkgs'
  puts rpm_metadata[:rpm_type][:other].join("\n")
end
