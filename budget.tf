# Cost guard. On a Free-plan account AWS cannot charge the card, but credits run
# out (and the account then closes), so this watches *gross* usage - credits are
# deliberately not subtracted, otherwise the number would read $0 forever.
# Expected steady state for this setup is ~ $12/month.

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit             = false # <- the important one
    include_refund             = false
    include_discount           = true
    include_recurring          = true
    include_subscription       = true
    include_support            = true
    include_tax                = true
    include_upfront            = true
    include_other_subscription = true
    use_amortized              = false
    use_blended                = false
  }

  # "You have already spent more than the budget this month."
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  # "At this rate you will end the month above the budget" - fires earlier, at
  # ~133% of the limit ($20 for the default $15), i.e. something unexpected is running.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 133
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}
