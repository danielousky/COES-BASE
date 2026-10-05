# config/initializers/delayed_job_config.rb

Delayed::Worker.destroy_failed_jobs = false
# El worker consulta la cola cada 5 s: el aviso de notas cargadas debe salir en segundos.
Delayed::Worker.sleep_delay = 5
Delayed::Worker.max_attempts = 3
# 90 min: la generación masiva de actas (MassiveActasGenerationJob) tarda mucho.
Delayed::Worker.max_run_time = 90.minutes
Delayed::Worker.read_ahead = 10
Delayed::Worker.default_queue_name = 'default'
Delayed::Worker.delay_jobs = !Rails.env.test?
Delayed::Worker.raise_signal_exceptions = :term
# En producción, a STDOUT para que `dokku logs coes-base -p worker` lo muestre; el archivo
# dentro del contenedor se pierde en cada despliegue. `sync`: sin terminal, Ruby retiene
# STDOUT en un búfer y los logs no aparecían.
if Rails.env.production?
  $stdout.sync = true
  Delayed::Worker.logger = Logger.new($stdout)
else
  Delayed::Worker.logger = Logger.new(Rails.root.join('log', 'delayed_job.log'))
end
