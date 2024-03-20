# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)

p '      Creado Primer Usuario!    '.center(200, '=') if user = User.create!(email: 'moros.daniel@gmail.com', first_name: 'Daniel Josué', last_name: 'Moros Castillo', ci: '15573230', password: 123123)

p '      Creado Primer Admin!    '.center(200, '=') if Admin.create!(user_id: user.id, role: :desarrollador)

p '      Creado Segundo Usuario!    '.center(200, '=') if user = User.create!(email: 'saavedraazuaje73@gmail.com', first_name: 'Carlos Alberto', last_name: 'Saavedra Azuaje', ci: '10264009', password: 123123)

p '      Creado Primer Admin!    '.center(200, '=') if Admin.create!(user_id: user.id, role: :desarrollador)

# p '      Creados Primeros Tipos de Períodos!    '.center(200, '=') if PeriodType.create([{code: 'I', name: 'Primero'}, {code: 'II', name: 'Segundo'}, {code: 'U', name: 'Único'}, {code: 'E', name: 'Especial (Intensivo)'}])

# p '      Creados Primeros Períodos!    '.center(200, '=') if Period.create([{year: 2022, period_type_id: 1}, {year: 2022, period_type_id: 2}])

# p '      Creado Primer Plan de Estudio!    '.center(200, '=') if StudyPlan.create(code: 'B001', name: 'Arquitecto', school_id: School.first.id)


# area = Area.where(name: "DISEÑO ARQUITECTÓNICO").first

# Area.create([{school_id: escuela.id, name: "Expresión", parent_area_id: area.id},
# {school_id: escuela.id, name: "Teoría de la Arquitectura", parent_area_id: area.id},
# {school_id: escuela.id, name: "Diseño Arquitectónico Sub", parent_area_id: area.id}])

# area = Area.where(name: "MÉTODOS").first

# Area.create([{school_id: escuela.id, name: "Matemáticas", parent_area_id: area.id},
# {school_id: escuela.id, name: "Investigación y Creatividad", parent_area_id: area.id},
# {school_id: escuela.id, name: "Informática", parent_area_id: area.id}])

# area = Area.where(name: "TECNOLOGÍA").first

# Area.create([{school_id: escuela.id, name: "Construcción", parent_area_id: area.id},
# {school_id: escuela.id, name: "Instalaciones", parent_area_id: area.id},
# {school_id: escuela.id, name: "Estructura", parent_area_id: area.id}])

Bank.create([{code: "0006", name: "Banco de Coro"},
{code: "0007", name: "Banfoandes"},
{code: "0008", name: "Banco Guayana"},
{code: "0102", name: "Banco de Venezuela"},
{code: "0104", name: "Banco Venezolano de Crédito"},
{code: "0105", name: "Banco Mercantil"},
{code: "0108", name: "Banco Provincial"},
{code: "0114", name: "Bancaribe"},
{code: "0115", name: "Banco Exterior"},
{code: "0116", name: "Banco Occidental de Descuento"},
{code: "0121", name: "Corp Banca"},
{code: "0128", name: "Banco Caroní"},
{code: "0133", name: "Banco Federal"},
{code: "0134", name: "Banesco"},
{code: "0137", name: "Banco Sofitasa"},
{code: "0138", name: "Banco Plaza"},
{code: "0140", name: "Banco Canarias de Venezuela"},
{code: "0141", name: "Banco Confederado"},
{code: "0145", name: "Banco de Comercio Exterior"},
{code: "0146", name: "Banco de la Gente Emprendedora"},
{code: "0148", name: "Total Bank"},
{code: "0151", name: "Banco Fondo Común"},
{code: "0156", name: "100% Banco"},
{code: "0157", name: "Banco Del Sur"},
{code: "0158", name: "Central Banco Universal"},
{code: "0161", name: "Banpro"},
{code: "0163", name: "Banco Del Tesoro"},
{code: "0166", name: "Banco Agrícola de Venezuela"},
{code: "0168", name: "Bancrecer"},
{code: "0169", name: "Mi Banco"},
{code: "0171", name: "Banco Activo"},
{code: "0172", name: "Bancamiga"},
{code: "0173", name: "Banco Internacional de Desarrollo"},
{code: "0174", name: "Banplus"},
{code: "0175", name: "Banco Bicentenario"},
{code: "0176", name: "Novo Banco"},
{code: "0177", name: "Banco de la Fuerza Armada Nacional Bolivariana"},
{code: "0190", name: "Citibank"},
{code: "0191", name: "Banco Nacional de Crédito"},
{code: "0601", name: "Instituto Municipal de Crédito Popular"}])


# e = School.first

# e.admission_types.create([{name: 'OPSU'},
# {name: 'OPSU/COLA'},
# {name: 'SIMADI'},
# {name: 'ACTA CONVENIO (DOCENTE)'},
# {name: 'ACTA CONVENIO (ADMIN)'},
# {name: 'ACTA CONVENIO (OBRERO)'},
# {name: 'DISCAPACIDAD'},
# {name: 'DIPLOMATICO'},
# {name: 'COMPONENTE DOCENTE'},
# {name: 'EQUIVALENCIA'},
# {name: 'ART. 25 (CULTURA)'},
# {name: 'ART. 25 (DEPORTE)'},
# {name: 'CAMBIO: 158'},
# {name: 'ART. 6'},
# {name: 'EGRESADO'},
# {name: 'SAMUEL ROBINSON'},
# {name: 'DELTA AMACURO'},
# {name: 'AMAZONAS'},
# {name: 'PRODES'},
# {name: 'CREDENCIALES'},
# {name: 'SIMULTANEOS'}])

p '      FINAL    '.center(400, '*')


