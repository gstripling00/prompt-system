# Prompt Management System - Terraform Configuration
# File: terraform/main.tf

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "prompt-management"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ============================================================
# VARIABLES
# ============================================================

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "admin_email" {
  description = "Admin user email"
  type        = string
}

# ============================================================
# GCS BUCKETS
# ============================================================

# Landing bucket for CSV uploads
resource "google_storage_bucket" "prompts_landing" {
  name          = "${var.project_id}-prompts-landing-${var.environment}"
  location      = var.region
  force_destroy = var.environment != "prod"
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }
}

# Bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-function-source-${var.environment}"
  location      = var.region
  force_destroy = true
  
  uniform_bucket_level_access = true
}

# Upload function source code
resource "google_storage_bucket_object" "function_code" {
  name   = "csv-processor-${filemd5("${path.module}/../functions/csv_processor.zip")}.zip"
  bucket = google_storage_bucket.function_source.name
  source = "${path.module}/../functions/csv_processor.zip"
}

# ============================================================
# BIGQUERY DATASET AND TABLES
# ============================================================

resource "google_bigquery_dataset" "prompts" {
  dataset_id                 = "prompts_${var.environment}"
  location                   = var.region
  description                = "Prompt Management System dataset"
  delete_contents_on_destroy = var.environment != "prod"
  
  access {
    role          = "OWNER"
    user_by_email = var.admin_email
  }
  
  access {
    role          = "roles/bigquery.dataViewer"
    special_group = "projectReaders"
  }
}

# Prompts Master Table (current versions)
resource "google_bigquery_table" "prompts_master" {
  dataset_id          = google_bigquery_dataset.prompts.dataset_id
  table_id            = "prompts_master"
  deletion_protection = var.environment == "prod"
  
  schema = jsonencode([
    {
      name = "prompt_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the prompt"
    },
    {
      name = "addie_phase"
      type = "STRING"
      mode = "REQUIRED"
      description = "ADDIE phase: Analysis, Design, Development, Implementation, or Evaluation"
    },
    {
      name = "sub_category"
      type = "STRING"
      mode = "NULLABLE"
      description = "Specific task type within the phase"
    },
    {
      name = "prompt_name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Descriptive name of the prompt"
    },
    {
      name = "prompt_text"
      type = "STRING"
      mode = "REQUIRED"
      description = "Full prompt template text"
    },
    {
      name = "tags"
      type = "STRING"
      mode = "REPEATED"
      description = "Tags for filtering and categorization"
    },
    {
      name = "prerequisites"
      type = "STRING"
      mode = "NULLABLE"
      description = "Required prior work or conditions"
    },
    {
      name = "expected_output"
      type = "STRING"
      mode = "NULLABLE"
      description = "Description of what this prompt produces"
    },
    {
      name = "version"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Version number"
    },
    {
      name = "version_notes"
      type = "STRING"
      mode = "NULLABLE"
      description = "Notes about this version"
    },
    {
      name = "author"
      type = "STRING"
      mode = "NULLABLE"
      description = "Email of the creator"
    },
    {
      name = "created_date"
      type = "DATE"
      mode = "NULLABLE"
      description = "Original creation date"
    },
    {
      name = "last_modified_date"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Last modification timestamp"
    },
    {
      name = "is_active"
      type = "BOOLEAN"
      mode = "REQUIRED"
      description = "Whether this prompt is currently active"
    },
    {
      name = "usage_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of times this prompt has been used"
    },
    {
      name = "avg_rating"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average user rating (1-5)"
    },
    {
      name = "embedding"
      type = "FLOAT"
      mode = "REPEATED"
      description = "Vector embedding for semantic search"
    }
  ])
}

# Prompts History Table (version history)
resource "google_bigquery_table" "prompts_history" {
  dataset_id          = google_bigquery_dataset.prompts.dataset_id
  table_id            = "prompts_history"
  deletion_protection = var.environment == "prod"
  
  time_partitioning {
    type  = "DAY"
    field = "changed_date"
  }
  
  schema = jsonencode([
    {
      name = "history_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for this history record"
    },
    {
      name = "prompt_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Reference to prompt_id in master table"
    },
    {
      name = "version"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Version number"
    },
    {
      name = "addie_phase"
      type = "STRING"
      mode = "REQUIRED"
      description = "ADDIE phase"
    },
    {
      name = "prompt_text"
      type = "STRING"
      mode = "REQUIRED"
      description = "Prompt text for this version"
    },
    {
      name = "changed_by"
      type = "STRING"
      mode = "NULLABLE"
      description = "Email of person who made the change"
    },
    {
      name = "changed_date"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the change occurred"
    },
    {
      name = "change_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of change: INSERT, UPDATE, DELETE, ARCHIVED"
    },
    {
      name = "version_notes"
      type = "STRING"
      mode = "NULLABLE"
      description = "Notes about this version"
    },
    {
      name = "previous_version"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Previous version number"
    }
  ])
}

# Usage Analytics Table
resource "google_bigquery_table" "usage_analytics" {
  dataset_id          = google_bigquery_dataset.prompts.dataset_id
  table_id            = "usage_analytics"
  deletion_protection = var.environment == "prod"
  
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  schema = jsonencode([
    {
      name = "usage_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for this usage event"
    },
    {
      name = "prompt_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Reference to prompt used"
    },
    {
      name = "user_email"
      type = "STRING"
      mode = "NULLABLE"
      description = "Email of user who used the prompt"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the prompt was used"
    },
    {
      name = "addie_phase_context"
      type = "STRING"
      mode = "NULLABLE"
      description = "ADDIE phase user was working in"
    },
    {
      name = "course_context"
      type = "STRING"
      mode = "NULLABLE"
      description = "Course or project context"
    },
    {
      name = "feedback_rating"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "User rating 1-5"
    },
    {
      name = "feedback_text"
      type = "STRING"
      mode = "NULLABLE"
      description = "Optional text feedback"
    },
    {
      name = "generation_successful"
      type = "BOOLEAN"
      mode = "NULLABLE"
      description = "Whether the prompt produced useful output"
    }
  ])
}

# ============================================================
# CLOUD FUNCTIONS
# ============================================================

# Service account for Cloud Function
resource "google_service_account" "csv_processor" {
  account_id   = "csv-processor-${var.environment}"
  display_name = "CSV Processor Function Service Account"
  description  = "Service account for prompt CSV processing function"
}

# Grant permissions to service account
resource "google_project_iam_member" "csv_processor_bq_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.csv_processor.email}"
}

resource "google_project_iam_member" "csv_processor_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.csv_processor.email}"
}

resource "google_project_iam_member" "csv_processor_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.csv_processor.email}"
}

# Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "csv_processor" {
  name        = "process-prompt-csv-${var.environment}"
  location    = var.region
  description = "Processes uploaded CSV files and loads prompts to BigQuery"
  
  build_config {
    runtime     = "python311"
    entry_point = "process_prompt_csv"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_code.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "512M"
    timeout_seconds                  = 300
    max_instance_request_concurrency = 1
    
    environment_variables = {
      PROJECT_ID   = var.project_id
      DATASET_ID   = google_bigquery_dataset.prompts.dataset_id
      ENVIRONMENT  = var.environment
    }
    
    service_account_email = google_service_account.csv_processor.email
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.prompts_landing.name
    }
    
    event_filters {
      attribute = "name"
      value     = "*.csv"
      operator  = "match-path-pattern"
    }
  }
}

# ============================================================
# DIALOGFLOW CX AGENT
# ============================================================

# Service account for Dialogflow CX agent
resource "google_service_account" "dialogflow_agent" {
  account_id   = "dialogflow-agent-${var.environment}"
  display_name = "Dialogflow CX Agent Service Account"
  description  = "Service account for Prompt Management Agent"
}

# Grant permissions
resource "google_project_iam_member" "dialogflow_bq_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.dialogflow_agent.email}"
}

resource "google_project_iam_member" "dialogflow_bq_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.dialogflow_agent.email}"
}

# Dialogflow CX Agent
resource "google_dialogflow_cx_agent" "prompts_agent" {
  display_name               = "Prompt Management Agent - ${upper(var.environment)}"
  location                   = var.region
  default_language_code      = "en"
  supported_language_codes   = ["en"]
  time_zone                  = "America/New_York"
  description                = "Agent for retrieving prompts based on ADDIE framework"
  enable_stackdriver_logging = true
  enable_spell_correction    = true
  
  speech_to_text_settings {
    enable_speech_adaptation = true
  }
  
  advanced_settings {
    logging_settings {
      enable_stackdriver_logging = true
      enable_interaction_logging = true
    }
  }
}

# ============================================================
# CLOUD RUN FOR WEBHOOK
# ============================================================

# Service account for webhook
resource "google_service_account" "webhook" {
  account_id   = "webhook-${var.environment}"
  display_name = "Webhook Service Account"
  description  = "Service account for Dialogflow webhook"
}

# Grant permissions
resource "google_project_iam_member" "webhook_bq_user" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.webhook.email}"
}

resource "google_project_iam_member" "webhook_bq_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.webhook.email}"
}

# ============================================================
# MONITORING & ALERTS
# ============================================================

# Notification channel (email)
resource "google_monitoring_notification_channel" "email" {
  display_name = "Prompt Management Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.admin_email
  }
}

# Alert policy for function failures
resource "google_monitoring_alert_policy" "function_errors" {
  display_name = "Prompt CSV Processing Errors - ${upper(var.environment)}"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type = \"cloud_function\" AND metric.type = \"cloudfunctions.googleapis.com/function/execution_count\" AND metadata.user_labels.environment = \"${var.environment}\" AND metric.label.status != \"ok\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
  
  alert_strategy {
    auto_close = "1800s"
  }
}

# Alert policy for BigQuery errors
resource "google_monitoring_alert_policy" "bigquery_errors" {
  display_name = "BigQuery Load Errors - ${upper(var.environment)}"
  combiner     = "OR"
  
  conditions {
    display_name = "BigQuery Job Failures"
    
    condition_threshold {
      filter          = "resource.type = \"bigquery_project\" AND metric.type = \"bigquery.googleapis.com/job/num_failed_jobs\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 3
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
}

# ============================================================
# OUTPUTS
# ============================================================

output "prompts_bucket" {
  description = "GCS bucket for CSV uploads"
  value       = google_storage_bucket.prompts_landing.name
}

output "bigquery_dataset" {
  description = "BigQuery dataset ID"
  value       = google_bigquery_dataset.prompts.dataset_id
}

output "cloud_function_url" {
  description = "Cloud Function URL"
  value       = google_cloudfunctions2_function.csv_processor.service_config[0].uri
}

output "dialogflow_agent_name" {
  description = "Dialogflow CX Agent name"
  value       = google_dialogflow_cx_agent.prompts_agent.name
}

output "environment" {
  description = "Deployment environment"
  value       = var.environment
}
