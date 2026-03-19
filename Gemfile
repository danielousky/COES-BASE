source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.1.2"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.0.4"

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"

# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 5.0"

# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Redis adapter to run Action Cable in production
gem "redis", "~> 4.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Sass to process CSS
gem "sassc-rails"
gem "cssbundling-rails"

# Own Gems:
gem "haml-rails", "~> 2.0"

# Authentication
gem "devise"

# Autorization
gem 'cancancan'

# Administration
gem 'rails_admin', '~> 3.1'#, '>= 3.1.2'
gem "rails_admin_import", "~> 3.0"

gem "autoprefixer-rails"
gem "font-awesome-sass", "~> 6.1"

gem "simple_form", github: "heartcombo/simple_form"

gem 'rqrcode'

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem 'image_processing', '~> 1.2'
gem 'mini_magick'

gem 'spreadsheet'

gem "aws-sdk-s3", require: false

# PDF Generation
gem 'wicked_pdf'
gem 'prawn'
gem 'prawn-table'
gem 'combine_pdf'

gem 'xlsxtream'

# Bitácora
gem "paper_trail"

# Delayed Job
gem 'delayed_job_active_record'
gem 'daemons'

group :development, :production do
  gem 'wkhtmltopdf-binary'
end

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
  gem "dotenv-rails" # Gema para Variables de Entorno
  gem "html2haml"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  gem 'annotate'
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  gem "webdrivers"
end
