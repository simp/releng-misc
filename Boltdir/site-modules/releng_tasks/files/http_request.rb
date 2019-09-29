require 'net/http'
require 'uri'
require 'json'
require 'openssl'

# A fit-for-most-purposes, MRI-compatible HTTP/S swiss army knife method
#
# @param [URI]  uri
# @param [Hash] opts options to configure the connection
# @option opts [String] :content_type
# @option opts [String] :body
# @option opts [String] :params
# @option opts [Hash<String,String>] :headers
# @option opts [Boolean] :use_ssl
# @option opts [<OpenSSL::SSL::VERIFY_PEER,OpenSSL::SSL::VERIFY_NONE>]
#   :verify_mode
# @option opts [Boolean] :show_debug_info
# @param [Net::HTTPGenericRequest] http_request_type
#
# @author Name Chris Tessmer <chris.tessmer@onyxpoint.com>
#
def http_request(uri, opts = {}, http_type = nil)
  http_type  ||= opts[:http_request_type] if opts[:http_request_type]
  http_type  ||= Net::HTTP::Post if opts[:body]
  http_type  ||= Net::HTTP::Get
  uri.query    = URI.encode_www_form(opts[:params]) if opts[:params]
  request      = http_type.new(uri)
  request.body = opts[:body] if opts[:body]

  request.content_type = opts.fetch(:content_type, 'application/json')
  opts.fetch(:headers, {}).each { |header, v| request[header] = v }

  http = Net::HTTP.new(uri.hostname, uri.port)
  http.set_debug_output($stdout) if opts[:show_debug_info]
  if opts[:use_ssl] || uri.scheme == 'https'
    http.use_ssl = true
    http.ca_file = opts[:ca_file] if opts.key?(:ca_file)
    http.verify_mode = opts[:verify_mode] || OpenSSL::SSL::VERIFY_PEER
  end

  response = http.request(request)
  unless response.code =~ /^2\d\d/
    msg = "\n\nERROR: Unexpected HTTP response from:" \
          "\n       #{response.uri}\n" \
          "\n       Response code_type: #{response.code_type} " \
          "\n       Response code:      #{response.code} " +
          (opts.fetch(:show_debug_response, false) ?
            "\n       Response body: " \
            "\n         #{JSON.parse(response.body)} \n\n" \
            "\n       Request body: " \
            "\n#{JSON.parse(request.body).to_yaml.split("\n").map { |x| ' ' * 8 + x }.join("\n")} \n\n"
           : '')
    raise(msg)
  end

  response
end

