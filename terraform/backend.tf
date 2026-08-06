terraform {
    backend "s3" {
        bucket = "test-bucket-beta7-terraform-state"
        key = "main/terraform.tfstate"
        region = "eu-north-1"
        encrypt = true
        use_lockfile = true
    }
}