# Envuelve un bloque en una transacción ACID y traduce los fallos a un resultado
# uniforme, para no repetir el patrón begin/transaction/rescue en cada controller
# y modelo del flujo crítico (alta de estudiante, histórico académico, reserva de
# cupo). Pensado para reusarse al replicar a FAU/ODONT.
#
# El bloque puede usar `raise ActiveRecord::Rollback` para revertir por una regla
# de negocio: eso NO se considera error (el resultado vuelve ok: true) y el
# llamador es responsable de su propio mensaje en ese caso.
#
# Uso:
#   res = Transaccionable.transaccion_atomica(contexto: "Foo#bar") { ... }
#   res.ok?    # => true si commiteó (o se revirtió por regla de negocio)
#   res.error  # => mensaje legible si una EXCEPCIÓN la revirtió (nil si ok)
module Transaccionable
  Resultado = Struct.new(:ok, :error, keyword_init: true) do
    def ok? = ok
  end

  module_function

  def transaccion_atomica(contexto: "transacción")
    ActiveRecord::Base.transaction { yield }
    Resultado.new(ok: true, error: nil)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("#{contexto}: RecordInvalid #{e.record&.errors&.full_messages&.to_sentence}")
    Resultado.new(ok: false, error: "(transacción revertida): #{e.record.errors.full_messages.to_sentence}")
  rescue StandardError => e
    Rails.logger.error("#{contexto}: #{e.class} #{e.message}")
    Resultado.new(ok: false, error: "(transacción revertida): ocurrió un error inesperado.")
  end
end
