resource "aws_s3_bucket" "data" {
  bucket = "acme-internal-data"
}

resource "aws_s3_bucket_acl" "data" {
  bucket = aws_s3_bucket.data.id
  acl    = "public-read"
}

resource "aws_security_group" "open" {
  name = "open-everything"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "default" {
  identifier        = "main-db"
  allocated_storage = 20
  engine            = "postgres"
  username          = "postgres"
  password          = "PlaintextPassword123!"
  publicly_accessible = true
  storage_encrypted   = false
  skip_final_snapshot = true
}
