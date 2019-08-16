Factory.define :user do |user|
   user.name                    "logan sease"
   user.email                   "lsease@gmail.com"
   user.password                "foobar2"
   user.password_confirmation   "foobar2"
   user.fb_user_id              6206197
end       



Factory.sequence :email do |n|
   "person-#{n}@example.com"
end