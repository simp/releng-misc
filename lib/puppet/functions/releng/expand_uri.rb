# @summary Expand [RFC 6570] URI Templates
# [RFC 6570]: https://datatracker.ietf.org/doc/html/rfc6570
Puppet::Functions.create_function(:'releng::expand_uri') do
  # @summary Expand [RFC 6570] URI Templates
  # @param uri_template URI Template string to expand
  # @param variables    variable->value mappings, used to expand URI Template
  # @example Expanding a simple URI template
  #   $uri_template = "http://api.github.com/v3/repos/{owner}/{repo}/releases"
  #   $uri = $uri_template.releng::expand_uri({
  #     'owner' => 'simp',
  #     'repo'  => 'releng-misc',
  #   })
  #   # =>  "http://api.github.com/v3/repos/simp/releng-misc/releases"
  # @return [String]    Expanded URI
  dispatch :expand_uri_template do
    param 'String', :uri_template
    param 'Hash', :variables
    return_type 'String'
  end

  # @api private
  def expand_uri_template(uri_template, variables)
    require 'addressable/template'
    template = Addressable::Template.new(uri_template)
    template.expand(variables).to_s
  end
end

