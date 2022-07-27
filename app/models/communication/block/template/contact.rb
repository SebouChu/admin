class Communication::Block::Template::Contact < Communication::Block::Template::Base

  has_component :name, :string
  has_component :address, :text
  has_component :zipcode, :string
  has_component :city, :string
  has_component :country, :string
  has_component :phone_numbers, :array
  has_component :emails, :array

  has_elements

end
