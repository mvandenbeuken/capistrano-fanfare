require 'capistrano'

module Capistrano::Fanfare::Bundler
  def self.load_into(configuration)
    configuration.load do
      set(:bundle_cmd)      { "#{current_release}/bin/bundle" }
      set :bundle_shebang,  "ruby-local-exec"

      set(:bundle_flags) do
        flags = "--deployment"
        flags << " --quiet" unless ENV['VERBOSE']
        flags << " --binstubs"
        flags << " --shebang #{bundle_shebang}"
        flags
      end

      set(:bundle_without) do
        without = [:development, :test]
        if exists?(:os_type) && exists?(:os_types)
          without += (fetch(:os_types) - Array(fetch(:os_type)))
        end
        without
      end

      set :bundle_binstub_template do
        <<-BINSTUB.gsub(/^ {10}/, '')
          #!/usr/bin/env #{bundle_shebang}
          #
          # This file was generated by capistrano.
          #

          require 'pathname'
          ENV['BUNDLE_GEMFILE'] ||= File.expand_path("../../Gemfile",
            Pathname.new(__FILE__).realpath)

          require 'rubygems'

          load Gem.bin_path('bundler', 'bundle')
        BINSTUB
      end

      require 'bundler/capistrano'

      set(:rake)  { "#{current_release}/bin/rake" }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Fanfare::Bundler.load_into(Capistrano::Configuration.instance)
end
