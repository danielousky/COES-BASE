PaperTrail.config.enabled = true
PaperTrail.config.has_paper_trail_defaults = {
  on: %i[create update destroy]
}
PaperTrail.config.version_limit = 30

PaperTrail.request.whodunnit = ->() {
  if Rails.const_defined?('Console') || File.basename($PROGRAM_NAME) == 'rake'
    "#{`whoami`.strip}: consola"
  else
    "#{`whoami`.strip}: #{File.basename($PROGRAM_NAME)} #{ARGV.join ' '}"
  end
}