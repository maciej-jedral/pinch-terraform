# Managed Postgres on Neon's free tier. Lives outside AWS on purpose: it survives
# the Free-plan account closing, and it scales to zero when idle (free-tier
# allowance is 100 compute-hours/month per project).

resource "neon_project" "pinch" {
  name       = var.project_name
  org_id     = var.neon_org_id
  region_id  = var.neon_region_id
  pg_version = var.neon_pg_version

  # Point-in-time-restore history. Free tier allows up to 6 hours; the provider
  # default (1 day) would be rejected on the free plan.
  history_retention_seconds = 21600
}
