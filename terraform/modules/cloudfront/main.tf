#------------------------------------------------------------------
# Module: CloudFront
#------------------------------------------------------------------
# NOTE: floci's GetDistribution omits OriginGroups, and aws provider 6.61.0
# dereferences it without a nil check (distribution.go:1150), segfaulting the
# provider mid-apply. The composite passes an empty list against floci so this
# module creates nothing. It is retained unchanged for real AWS.
#------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "floci_cloudfront_oac" {
  for_each = local.distributions

  name                              = "${each.key}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "floci_cloudfront_distribution" {
  for_each = local.distributions

  enabled             = true
  default_root_object = each.value.default_root_object
  aliases             = each.value.aliases
  comment             = each.value.comment

  origin {
    domain_name              = each.value.bucket_regional_domain_name
    origin_id                = each.value.bucket_id
    origin_access_control_id = aws_cloudfront_origin_access_control.floci_cloudfront_oac[each.key].id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = each.value.bucket_id
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = each.value.acm_certificate_arn
    cloudfront_default_certificate = each.value.acm_certificate_arn == null
    ssl_support_method             = each.value.acm_certificate_arn == null ? null : "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = each.key }
  )
}
