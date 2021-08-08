# @summary Return data from each `mod` item in a Puppetfile
Puppet::Functions.create_function(:'releng::parse_puppetfile') do

  # Return data from each `mod` item in a Puppetfile
  # @param content Content of Puppetfile
  # @return [Hash] Data for each `mod` entry (structure: `<path> => <data>`)
  dispatch :parse_puppetfile do
    param 'String', :content
    return_type 'Hash'
  end

  # @api private
  def parse_puppetfile(content)
    Puppet.lookup(:bolt_executor) {}&.report_function_call(self.class.name)
    pdsl = PuppetfileDSLReader.new(content)

    # Stringify all keys (because Puppet can't handle symbols)
    Hash[pdsl.modules.map{|k,v| [v[:mod_rel_path], Hash[v.map{|x,y| [x.to_s,y]} ]] }]
  end

  # Barebones implementation of the Puppetfile DSL
  # @api private
  class PuppetfileDSL
    @lines = []
    def initialize(librarian)
      @librarian = librarian
    end

    def mod(name, args = nil)
      Puppet.debug("== Puppetfile:  #{__method__.to_s} : name='#{name}'" )
      @librarian.add_module(name, args)
    end

    def forge(location)
      Puppet.debug("== Puppetfile:  #{__method__.to_s} : location='#{location}'" )
      @librarian.set_forge(location)
    end

    def moduledir(location)
      Puppet.debug("== Puppetfile:  #{__method__.to_s} : location='#{location}'" )
      @librarian.set_moduledir(location)
    end

    def method_missing(method, *args)
      raise NoMethodError, _("unrecognized declaration '%{method}'") % {method: method}
    end
  end


  # Provides methods to build data structure of Puppetfile `mod` items
  # @api private
  class PuppetfileDSLReader

    attr_reader :modules
    attr_reader :module_dirs

    def initialize(puppetfile_data)
      @module_dir = nil
      @module_dirs = []
      @modules = {}

      dsl = PuppetfileDSL.new(self)
      dsl.instance_eval(puppetfile_data)
    end

    def self.from_puppetfile(path)
      self.new(File.read(path))
    end

    def add_module(name, args)
      install_path = (args.is_a?(Hash) && args[:install_path]) || @module_dir

      # R10k-style `mod` dir name, without the namespace from the `mod` entry
      mod_name = name.split(%r{[-/]}).last

      # Relative path to local mod dir, using `mod` item's `-<name>` segment
      # (Useful for cloning `mod` items to the same paths as R10k would)
      mod_rel_path = File.join(install_path, mod_name)

      # Relative path to local mod dir, using the _unchopped_ `mod` name
      # (Useful for cloning unique `mod` names w/identical `-<name>` segments)
      rel_path = File.join(install_path,name)

      args ||= {}
      info = args.merge({
        :name         => name,
        :rel_path     => rel_path,
        :mod_name     => mod_name,
        :mod_rel_path => mod_rel_path,
        :install_path => install_path,
      })

      info[:repo_name] = File.basename(args[:git], '.git') if args.key? :git
      @modules[rel_path]=info
    end

    # Unused (valid in a Puppetfile, but we don't have a use for it)
    def set_forge(location)
    end

    def set_moduledir(location)
      @module_dirs << location
      @module_dir = location
    end

    def each
      @modules.each
    end
  end
end

