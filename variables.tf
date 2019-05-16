##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {
    default = "/home/frederique/Downloads/demo.pem"
}
variable "key_name" {
    default = "demo"
}
variable "instance_count" {
    default = "2"
}
