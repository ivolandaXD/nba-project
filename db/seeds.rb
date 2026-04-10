admin_email = ENV.fetch('ADMIN_EMAIL', 'admin@example.com')
admin_password = ENV.fetch('ADMIN_PASSWORD', 'changeme123')

User.find_or_initialize_by(email: admin_email).tap do |u|
  u.password = admin_password
  u.password_confirmation = admin_password
  u.role = 'admin'
  u.save!
end

Rails.logger.info "Seeded admin: #{admin_email}"
