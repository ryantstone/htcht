require 'htcht/helpers/general_helpers'
require 'htcht/helpers/name_helpers'
require 'htcht/helpers/version_helpers'

module Htcht
  module CLI
    module Rails

      class Rails < Thor
        include Thor::Actions
        include Htcht::Helpers::GeneralHelpers
        include Htcht::Helpers::NameHelpers
        include Htcht::Helpers::VersionHelpers

        def self.source_root
          File.dirname(__FILE__)
        end

        desc 'new AppName', 'Create a new base Rails App inside a Docker Container with Postgres setup as the database.'
        method_option :verbose, type: :boolean, default: false, :aliases => '-v', :desc => 'default: [--no-verbose] By default rails new will be run with the quiet flag, this turns it off.'
        method_option :api, type: :boolean, default: false, :aliases => '-a', :desc => 'default: [--no-api] Generate Rails App in API mode.'
        method_option :init, type: :boolean, default: false, :aliases => '-i', :desc => 'default: [--no-init] Generate a base Rails app with custom Gemfile and configs. (This along with "--api" is the base for new Rails APIs at Trim Agency).'
        method_option :test, type: :boolean, default: false, :desc => 'default: [--no-test]'
        method_option :ruby_version, type: :string, :desc => "default: [latest version] Set the version of Ruby to be used."
        method_option :rails_version, type: :string, :desc => "default: [latest version] Set the version of Rails to be used."
        def new(appname)
          unless docker_running?
            puts 'Check that Docker is installed and running'
            return
          end

          options[:ruby_version] ||= latest_ruby
          options[:rails_version] ||= latest_rails

          # Format the appname as snake case for folders, etc.
          snake_name = snake_casify(appname)

          rails_new_command = 'docker-compose run app rails new . --database=postgresql --skip-bundle'

          # Set the application template
          # TODO: Refactor to be dynamic from a directory
          if options[:init] && options[:api]
            template_path = "#{snake_name}/api_init_template.rb"
            copy_file('templates/api_init_template.rb', template_path)
            copy_file('templates/api_build_files/user_spec.rb', "#{snake_name}/build_files/user_spec.rb")
            copy_file('templates/api_build_files/users.rb', "#{snake_name}/build_files/users.rb")
            copy_file('templates/api_build_files/email_validator.rb', "#{snake_name}/build_files/email_validator.rb")
            copy_file('templates/api_build_files/factory_girl.rb', "#{snake_name}/build_files/factory_girl.rb")
            copy_file('templates/api_build_files/shoulda_matchers.rb', "#{snake_name}/build_files/shoulda_matchers.rb")
            copy_file('templates/api_build_files/rails_helper.rb', "#{snake_name}/build_files/rails_helper.rb")
            copy_file('templates/api_build_files/seeds.rb', "#{snake_name}/build_files/seeds.rb")
            copy_file('templates/api_build_files/active_model_serializers.rb', "#{snake_name}/build_files/active_model_serializers.rb")
            copy_file('templates/api_build_files/.rubocop.yml', "#{snake_name}/build_files/.rubocop.yml")
            rails_new_command.concat(' -m api_init_template.rb -T')
          elsif options[:init]
            puts "--init must be used with --api for now."
            return
          else
            template_path = "#{snake_name}/default_template.rb"
            copy_file 'templates/default_template.rb', template_path
            rails_new_command.concat(' -m default_template.rb')
          end

          if defined? template_path
            add_app_names_to_template(path: template_path,
                                      appname: appname,
                                      snake_name: snake_name)
          end

          # Copy this over so that Docker can run Rails new
          copy_file 'BaseGemfile', "#{snake_name}/Gemfile"
          rails_new_command.concat(' --force')

          if options[:api]
            rails_new_command.concat(' --api')
          end

          unless options[:verbose]
            rails_new_command.concat(' --quiet')
          end

          puts "Creating new Rails API with name: #{appname}"

          if options[:test]
            puts "Here is the command:"
            puts rails_new_command
            return
          end

          empty_directory(snake_name)
          copy_file('docker-compose.yml', "#{snake_name}/docker-compose.yml")
          copy_file('Dockerfile', "#{snake_name}/Dockerfile")
          gsub_file("#{snake_name}/Dockerfile", 'set_ruby_version', options[:ruby_version])
          gsub_file("#{snake_name}/Dockerfile", 'set_rails_version', options[:rails_version])
          gsub_file("#{snake_name}/Gemfile", 'set_ruby_version', options[:ruby_version])
          gsub_file("#{snake_name}/Gemfile", 'set_rails_version', options[:rails_version])


          inside(snake_name) do

            # Build the containers
            run('docker-compse build')

            # Run the command to generate a new rails app
            run(rails_new_command)

            # Edit the Dockerfile and rebuild the app now that it has a Gemfile and Gemfile.lock
            gsub_file('Dockerfile', "RUN gem install rails", '#RUN gem install rails')
            gsub_file('Dockerfile', '#COPY Gemfile Gemfile.lock ./', 'COPY Gemfile Gemfile.lock ./')
            gsub_file('Dockerfile', '#RUN gem install bundler && bundle install --jobs 20 --retry 5', 'RUN gem install bundler && bundle install --jobs 20 --retry 5')
            run("docker rmi #{appname.downcase}_app -f")
            run('docker-compose build')

            run('docker-compose run app rake db:create')
            run('docker-compose run app rake db:migrate')

            # Clean up the template and build files
            if options[:init] && options[:api]
              remove_file("api_init_template.rb")
              remove_dir("build_files/")
            else
              remove_file("default_template.rb")
            end
          end
        end

        private

        def add_app_names_to_template(path:, appname:, snake_name:)
          gsub_file(path, 'set_appname', appname)
          gsub_file(path, 'set_snake_name', snake_name)
        end
      end
    end
  end
end
