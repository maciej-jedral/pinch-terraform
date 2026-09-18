# DNS for the domain, hosted on Porkbun's nameservers (the registrar). Lives
# outside AWS on purpose, like Neon: it survives the Free-plan account closing.
#
#   pinchapp.fyi       A      -> Vercel (frontend)
#   www.pinchapp.fyi   CNAME  -> Vercel (redirects to the apex, configured in Vercel)
#   api.pinchapp.fyi   A      -> our Elastic IP (backend; Caddy on the box does TLS)
#
# Porkbun pre-creates parking records on a new domain (ALIAS @ and CNAME * ->
# pixie.porkbun.com). They are not managed here and must be deleted once by hand
# (dashboard or API), otherwise the apex record conflicts. See README.

resource "porkbun_dns_record" "apex" {
  domain  = var.domain
  type    = "A"
  content = var.vercel_apex_a
  notes   = "Vercel (frontend) - managed by Terraform"
}

resource "porkbun_dns_record" "www" {
  domain    = var.domain
  subdomain = "www"
  type      = "CNAME"
  content   = var.vercel_www_cname
  notes     = "Vercel (redirects to apex) - managed by Terraform"
}

resource "porkbun_dns_record" "api" {
  domain    = var.domain
  subdomain = "api"
  type      = "A"
  content   = aws_eip.backend.public_ip
  notes     = "EC2 backend (Elastic IP) - managed by Terraform"
}
