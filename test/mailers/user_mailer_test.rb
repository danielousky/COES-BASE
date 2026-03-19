require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "welcome" do
    user = users(:admin_user)
    mail = UserMailer.welcome(user)
    assert_equal "¡Bienvenido a Coes!", mail.subject
    assert_includes mail.to.first, user.email
  end
end
