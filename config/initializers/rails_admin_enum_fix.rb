# Fix: ActiveRecordEnum#parse_input calls deserialize() on form values,
# which breaks string enum keys (e.g., "Componente".to_i => 0 => "Semestral").
# This patch allows string keys to pass through directly when they are valid
# enum keys, and only deserializes integer-like values.
module RailsAdmin
  module Config
    module Fields
      module Types
        class ActiveRecordEnum < Enum
          def parse_input(params)
            value = params[name]
            return unless value.present?

            enum_mapping = abstract_model.model.defined_enums[name.to_s]
            if enum_mapping&.key?(value)
              # Value is already a valid enum key (e.g., "Componente"), use directly
              return
            end

            # Otherwise deserialize (e.g., integer string "4" -> "Componente")
            params[name] = parse_input_value(value)
          end
        end
      end
    end
  end
end
