require "test_helper"

class BillboardsControllerTest < ActionDispatch::IntegrationTest
  # BillboardsController no tiene rutas en routes.rb.
  # La gestión de carteleras se realiza a través de Rails Admin.
  # Estos tests validan el modelo Billboard directamente.

  test "should create billboard with content" do
    billboard = Billboard.new(active: true)
    billboard.content = "Contenido de prueba"
    assert billboard.save, "No se pudo guardar la cartelera: #{billboard.errors.full_messages.to_sentence}"
  end

  test "should not create billboard without content" do
    billboard = Billboard.new(active: true)
    assert_not billboard.save, "Se guardó una cartelera sin contenido"
  end

  test "should toggle active status" do
    billboard = Billboard.new(active: false)
    billboard.content = "Contenido"
    billboard.save!
    billboard.update!(active: true)
    assert billboard.active?, "La cartelera debería estar activa"
  end

  test "scope activas should return only active billboards" do
    Billboard.destroy_all
    b1 = Billboard.create!(content: "Activa", active: true)
    b2 = Billboard.create!(content: "Inactiva", active: false)
    assert_includes Billboard.activas, b1
    assert_not_includes Billboard.activas, b2
  end

  test "should have paper trail on create" do
    billboard = Billboard.new(active: true)
    billboard.content = "Con auditoría"
    billboard.save!
    assert billboard.versions.any?, "Debería tener historial de versiones"
  end

  test "should have paper trail on update" do
    billboard = Billboard.create!(content: "Original", active: true)
    billboard.update!(active: false)
    assert billboard.versions.count >= 2, "Debería tener al menos 2 versiones"
  end

  test "should have paper trail on destroy" do
    billboard = Billboard.create!(content: "A eliminar", active: true)
    billboard.destroy!
    assert PaperTrail::Version.where(item_type: 'Billboard', item_id: billboard.id).any?
  end
end
