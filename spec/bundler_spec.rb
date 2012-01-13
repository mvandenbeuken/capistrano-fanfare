require 'minitest/autorun'
require 'minitest/capistrano'
require 'capistrano/fanfare'
require 'capistrano/fanfare/bundler'

#
# Rake mixes in FileUtils methods into Capistrano::Configuration::Namespace as
# private methods which will cause a method/task namespace collision when the
# `bundle:install' task is created.
#
# So, if we are in a Rake context, nuke :install in the Namespace class--we
# won't be using it directly in this codebase but this feels so very, very
# wrong (here be dragons).
#
if defined?(Rake::DSL)
  Capistrano::Configuration::Namespaces::Namespace.class_eval { undef :install }
end

describe Capistrano::Fanfare::Bundler do
  before do
    @config = Capistrano::Configuration.new
    Capistrano::Fanfare::Bundler.load_into(@config)
    @config.extend(MiniTest::Capistrano::ConfigurationExtension)
    @orig_config = Capistrano::Configuration.instance
    Capistrano::Configuration.instance = @config

    @config.set :current_release, "/srv/gemmy/releases/thisone"
  end

  after do
    Capistrano::Configuration.instance = @orig_config
  end

  describe "for variables" do
    it "sets :bundle_cmd to 'bundle'" do
      @config.fetch(:bundle_cmd).must_equal "bundle"
    end

    it "sets :bundle_shebang to 'ruby-local-exec'" do
      @config.fetch(:bundle_shebang).must_equal "ruby-local-exec"
    end

    it "add :current_path/bin to the default_environment PATH" do
      @config.set :current_path, "/tmp/app/current"

      @config.fetch(:default_environment)['PATH'].must_equal "/tmp/app/current/bin:$PATH"
    end

    it "sets :bundle_binstub_template to the binstub script" do
      @config.set :bundle_shebang, "jruby"

      @config.fetch(:bundle_binstub_template).must_equal <<-BINSTUB
#!/usr/bin/env jruby
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

    it "sets :rake to 'rake'" do
      @config.fetch(:rake).must_equal "rake"
    end

    describe ":bundle_flags" do
      after do
        ENV.delete('VERBOSE')
      end

      it "contains --deployment" do
        @config.fetch(:bundle_flags).must_match /--deployment/
      end

      it "contains --binstubs" do
        @config.fetch(:bundle_flags).must_match /--binstubs/
      end

      it "contains --shebang <shebang_bin>" do
        @config.set :bundle_shebang, "bangbang"

        @config.fetch(:bundle_flags).must_match /--shebang bangbang/
      end

      it "contains --quiet by default" do
        @config.fetch(:bundle_flags).must_match /--quiet/
      end

      it "does not contain --quiet if ENV['VERSBOSE'] is set" do
        ENV['VERBOSE'] = "yes"

        @config.fetch(:bundle_flags).wont_match /--quiet/
      end
    end

    describe ":bundle_without" do
      it "contains :development and :test groups" do
        @config.fetch(:bundle_without).must_include :development
        @config.fetch(:bundle_without).must_include :test
      end

      it "contains all other values from :os_types if the :os_type variable exists" do
        @config.set :os_types, [:fizz, :buzz, :rocketships]
        @config.set :os_type, :rocketshipos

        @config.fetch(:bundle_without).must_include :fizz
        @config.fetch(:bundle_without).must_include :buzz
        @config.fetch(:bundle_without).must_include :development
        @config.fetch(:bundle_without).must_include :test
      end
    end
  end

  describe "for namespace :bundle" do
    it "creates a bundle:install task" do
      @config.must_have_task "bundle:install"
    end

    it "calls bundle:install task after deploy:finalize_update" do
      @config.must_have_callback_after "deploy:finalize_update", "bundle:install"
    end

    describe "task :create_binstub_script" do
      it "creates bin/bundle binstub script" do
        @config.set :shared_path, "/tmp/app/shared"
        @config.set :bundle_binstub_template, "thescript"
        @config.find_and_execute_task("bundle:create_binstub_script")

        @config.must_have_run "mkdir -p /tmp/app/shared/bin"
        @config.must_have_put "/tmp/app/shared/bin/bundle", "thescript"
      end

      it "gets called after deploy:setup task" do
        @config.must_have_callback_after "deploy:setup", "bundle:create_binstub_script"
      end
    end

    describe "task :cp_bundle_binstub" do
      it "copies bin/bundle into current_path" do
        @config.set :shared_path, "/tmp/app/shared"
        @config.set :current_path, "/tmp/app/current"
        @config.find_and_execute_task("bundle:cp_bundle_binstub")

        @config.must_have_run [
          "mkdir -p /tmp/app/current/bin",
          "cp /tmp/app/shared/bin/bundle /tmp/app/current/bin/bundle",
          "chmod 0755 /tmp/app/current/bin/bundle"
        ].join(" && ")
      end

      it "gets called after deploy:update_code task" do
        @config.must_have_callback_before "deploy:finalize_update", "bundle:cp_bundle_binstub"
      end
    end
  end
end
