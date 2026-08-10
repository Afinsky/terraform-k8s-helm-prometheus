profile     = "terraform"
environment = "dev"
region      = "us-east-1"

vpc = {
  csai = {
    cidr             = "10.30.0.0/16"
    azs              = ["us-east-1c", "us-east-1f"]
    private_subnets  = ["10.30.10.0/24", "10.30.11.0/24"]
    public_subnets   = ["10.30.20.0/24", "10.30.21.0/24"]
    database_subnets = ["10.30.30.0/24", "10.30.31.0/24"]
  }
}

domain_registrant_contact = {
  first_name     = "Aliaksei"
  last_name      = "Batsian"
  contact_type   = "PERSON"
  address_line_1 = "Budki Szczesliwickie 25"
  city           = "Warsaw"
  zip_code       = "02-460"
  country_code   = "PL"
  email          = "a.afinsky@gmail.com"
  phone_number   = "+48571034412"
}
