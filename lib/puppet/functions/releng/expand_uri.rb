# Parse Puppetfile contents
Puppet::Functions.create_function(:'releng::expand_uri') do
  dispatch :expand_uri_template do
    param 'String', :uri_template
    param 'Hash', :variables
    return_type 'String'
  end

  def expand_uri_template(uri_template, variables)
    require 'addressable/template'
    template = Addressable::Template.new(uri_template)
    template.expand(variables).to_s
  end
end

