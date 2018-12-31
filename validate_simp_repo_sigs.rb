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

  _opts = OptionParser.new do |opts|
    opts.banner = USAGE

    opts.separator ""

    opts.on(
      '-t REPORT_TYPE',
      '--report-type REPORT_TYPE',
      'Output a report of this type. May be one of:',
      '  * invalid (default)',
      '  * valid'
    ) do |arg|
      valid_reports = [
        'invalid',
        'valid'
      ]

      unless valid_reports.include?(arg)
        $stderr.puts("Error: report-type must be one of:\n  * #{valid_reports.join("\n  * ")}")
        exit 1
      end

      options.report_type = arg.strip
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

def process_rpms(tgt_dir, valid_sigs)
  rpm_metadata = {
    :valid => {},
    :invalid => {}
  }

  rpms = (`find #{tgt_dir} -type f -name "*.rpm"`).lines.map{|f| File.absolute_path(f.strip)}

  rpms.each do |rpm|
    rpm_info = %x{rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE} %{SIGPGP:pgpsig} %{SIGGPG:pgpsig}\\n' #{rpm} 2>/dev/null}

    rpm_name = rpm_info.split(/\s+/).first

    if rpm_info =~ /Key ID (\S+)/
      key_id = $1.upcase

      if valid_sigs[key_id]
        rpm_metadata[:valid][valid_sigs[key_id]] ||= []
        rpm_metadata[:valid][valid_sigs[key_id]] << "#{key_id} => #{rpm_name}"
      else
        rpm_metadata[:invalid][rpm_name] = "Unknown Key => #{key_id}"
      end
    else
      rpm_metadata[:invalid][rpm_name] = 'Not Signed'
    end
  end

  return rpm_metadata
end

options = parse_options

valid_sigs = extract_gpgkeys(options.target_dir)
rpm_metadata = process_rpms(options.target_dir, valid_sigs)

if options.report_type == 'valid'
  rpm_metadata[:valid].each do |k,v|
    puts %{* #{k}\n\n  - #{v.join("\n  - ")}}
    puts "\n"
  end
end

if options.report_type == 'invalid'
  if rpm_metadata[:invalid].empty?
    puts 'No invalid RPMs found!'
  else
    puts 'Invalid RPMs:'

    rpm_metadata[:invalid].each do |k,v|
      puts "* #{k}: #{v}"
    end

    exit 2
  end
end
