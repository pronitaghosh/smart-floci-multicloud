#------------------------------------------------------------------
# Module: S3 Buckets
#------------------------------------------------------------------

resource "aws_s3_bucket" "floci_bucket" {
  for_each = local.buckets

  bucket = each.key

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = each.key }
  )
}

resource "aws_s3_bucket_versioning" "floci_bucket_versioning" {
  for_each = local.buckets

  bucket = aws_s3_bucket.floci_bucket[each.key].id

  versioning_configuration {
    status = each.value.versioning
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "floci_bucket_sse" {
  for_each = local.encrypted_buckets

  bucket = aws_s3_bucket.floci_bucket[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = each.value.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "floci_bucket_pab" {
  for_each = local.public_blocked

  bucket = aws_s3_bucket.floci_bucket[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "floci_bucket_policy" {
  for_each = local.cloudfront_read

  bucket = aws_s3_bucket.floci_bucket[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontServicePrincipal"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.floci_bucket[each.key].arn}/*"
    }]
  })
}
