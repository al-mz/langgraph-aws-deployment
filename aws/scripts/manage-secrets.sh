#!/bin/bash

# Parameter Store Management Script
# Manages secrets and configuration in AWS Parameter Store

set -e

# Configuration
REGION=${AWS_DEFAULT_REGION:-us-east-1}
PARAMETER_PREFIX="/langgraph"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Put parameter in Parameter Store
put_parameter() {
    local name="$1"
    local value="$2"
    local type="${3:-SecureString}"
    local description="$4"
    
    log_info "Setting parameter: $name"
    
    aws ssm put-parameter \
        --name "$name" \
        --value "$value" \
        --type "$type" \
        --description "$description" \
        --region "$REGION" \
        --overwrite \
        >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Parameter $name set successfully"
    else
        log_error "Failed to set parameter $name"
        return 1
    fi
}

# Get parameter from Parameter Store
get_parameter() {
    local name="$1"
    local decrypt="${2:-true}"
    
    if [ "$decrypt" = "true" ]; then
        aws ssm get-parameter \
            --name "$name" \
            --with-decryption \
            --region "$REGION" \
            --query 'Parameter.Value' \
            --output text 2>/dev/null
    else
        aws ssm get-parameter \
            --name "$name" \
            --region "$REGION" \
            --query 'Parameter.Value' \
            --output text 2>/dev/null
    fi
}

# Delete parameter from Parameter Store
delete_parameter() {
    local name="$1"
    
    log_info "Deleting parameter: $name"
    
    aws ssm delete-parameter \
        --name "$name" \
        --region "$REGION" \
        >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Parameter $name deleted successfully"
    else
        log_warning "Parameter $name not found or already deleted"
    fi
}

# List parameters
list_parameters() {
    local environment="$1"
    local prefix="${PARAMETER_PREFIX}"
    
    if [ -n "$environment" ]; then
        prefix="${PARAMETER_PREFIX}/${environment}"
    fi
    
    log_info "Listing parameters with prefix: $prefix"
    
    aws ssm get-parameters-by-path \
        --path "$prefix" \
        --recursive \
        --region "$REGION" \
        --query 'Parameters[*].[Name,Type,LastModifiedDate,Description]' \
        --output table
}

# Setup all required parameters for an environment
setup_environment_parameters() {
    local environment="$1"
    local env_prefix="${PARAMETER_PREFIX}/${environment}"
    
    log_info "Setting up parameters for environment: $environment"
    
    # OpenAI API Key
    if [ -z "$OPENAI_API_KEY" ]; then
        read -p "Enter OpenAI API Key: " -s OPENAI_API_KEY
        echo
    fi
    
    if [ -n "$OPENAI_API_KEY" ]; then
        put_parameter \
            "${env_prefix}/openai-api-key" \
            "$OPENAI_API_KEY" \
            "SecureString" \
            "OpenAI API key for LangGraph agent"
    else
        log_error "OpenAI API Key is required"
        return 1
    fi
    
    # Application Configuration
    put_parameter \
        "${env_prefix}/config/log-level" \
        "${LOG_LEVEL:-INFO}" \
        "String" \
        "Log level for the application"
    
    put_parameter \
        "${env_prefix}/config/environment" \
        "$environment" \
        "String" \
        "Environment name"
    
    put_parameter \
        "${env_prefix}/config/region" \
        "$REGION" \
        "String" \
        "AWS region"
    
    # Agent Configuration
    put_parameter \
        "${env_prefix}/agent/model" \
        "${OPENAI_MODEL:-gpt-4}" \
        "String" \
        "OpenAI model for the agent"
    
    put_parameter \
        "${env_prefix}/agent/timeout" \
        "${AGENT_TIMEOUT:-30}" \
        "String" \
        "Agent timeout in seconds"
    
    put_parameter \
        "${env_prefix}/agent/max-iterations" \
        "${MAX_ITERATIONS:-10}" \
        "String" \
        "Maximum agent iterations"
    
    # Optional: Database configuration (if using)
    if [ -n "$DATABASE_URL" ]; then
        put_parameter \
            "${env_prefix}/database/url" \
            "$DATABASE_URL" \
            "SecureString" \
            "Database connection URL"
    fi
    
    # Optional: Redis configuration (if using)
    if [ -n "$REDIS_URL" ]; then
        put_parameter \
            "${env_prefix}/redis/url" \
            "$REDIS_URL" \
            "SecureString" \
            "Redis connection URL"
    fi
    
    log_success "Environment parameters setup completed for: $environment"
}

# Cleanup environment parameters
cleanup_environment_parameters() {
    local environment="$1"
    local env_prefix="${PARAMETER_PREFIX}/${environment}"
    
    log_info "Cleaning up parameters for environment: $environment"
    
    # Get all parameters for the environment
    PARAMETERS=$(aws ssm get-parameters-by-path \
        --path "$env_prefix" \
        --recursive \
        --region "$REGION" \
        --query 'Parameters[*].Name' \
        --output text)
    
    if [ -n "$PARAMETERS" ]; then
        for param in $PARAMETERS; do
            delete_parameter "$param"
        done
        log_success "Environment parameters cleanup completed for: $environment"
    else
        log_info "No parameters found for environment: $environment"
    fi
}

# Backup parameters to file
backup_parameters() {
    local environment="$1"
    local output_file="$2"
    local env_prefix="${PARAMETER_PREFIX}/${environment}"
    
    log_info "Backing up parameters for environment: $environment"
    
    aws ssm get-parameters-by-path \
        --path "$env_prefix" \
        --recursive \
        --with-decryption \
        --region "$REGION" \
        --output json > "$output_file"
    
    if [ $? -eq 0 ]; then
        log_success "Parameters backed up to: $output_file"
    else
        log_error "Failed to backup parameters"
        return 1
    fi
}

# Restore parameters from file
restore_parameters() {
    local environment="$1"
    local input_file="$2"
    
    log_info "Restoring parameters for environment: $environment from: $input_file"
    
    if [ ! -f "$input_file" ]; then
        log_error "Backup file not found: $input_file"
        return 1
    fi
    
    # Parse JSON and restore parameters
    jq -r '.Parameters[] | [.Name, .Value, .Type, (.Description // "")] | @tsv' "$input_file" | \
    while IFS=$'\t' read -r name value type description; do
        put_parameter "$name" "$value" "$type" "$description"
    done
    
    log_success "Parameters restored for environment: $environment"
}

# Show help
show_help() {
    echo "Usage: $0 <command> [arguments]"
    echo
    echo "Commands:"
    echo "  put <name> <value> [type] [description]  Put a parameter"
    echo "  get <name> [decrypt]                     Get a parameter"
    echo "  delete <name>                            Delete a parameter"
    echo "  list [environment]                       List parameters"
    echo "  setup <environment>                      Setup all parameters for environment"
    echo "  cleanup <environment>                    Delete all parameters for environment"
    echo "  backup <environment> <file>              Backup parameters to file"
    echo "  restore <environment> <file>             Restore parameters from file"
    echo
    echo "Arguments:"
    echo "  environment    Environment name (development, staging, production)"
    echo "  name          Parameter name (with full path)"
    echo "  value         Parameter value"
    echo "  type          Parameter type (String, StringList, SecureString)"
    echo "  description   Parameter description"
    echo "  file          Backup/restore file path"
    echo
    echo "Environment Variables:"
    echo "  AWS_DEFAULT_REGION    AWS region (default: us-east-1)"
    echo "  OPENAI_API_KEY        OpenAI API key"
    echo "  LOG_LEVEL             Application log level"
    echo "  OPENAI_MODEL          OpenAI model name"
    echo "  AGENT_TIMEOUT         Agent timeout in seconds"
    echo "  MAX_ITERATIONS        Maximum agent iterations"
    echo
    echo "Examples:"
    echo "  $0 put /langgraph/dev/test-key test-value"
    echo "  $0 get /langgraph/dev/test-key"
    echo "  $0 setup development"
    echo "  $0 list development"
    echo "  $0 backup production backup.json"
    echo "  $0 restore development backup.json"
}

# Main function
main() {
    local command="$1"
    
    case "$command" in
        put)
            if [ $# -lt 3 ]; then
                log_error "Usage: $0 put <name> <value> [type] [description]"
                exit 1
            fi
            put_parameter "$2" "$3" "${4:-SecureString}" "$5"
            ;;
        get)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 get <name> [decrypt]"
                exit 1
            fi
            value=$(get_parameter "$2" "${3:-true}")
            if [ -n "$value" ]; then
                echo "$value"
            else
                log_error "Parameter not found: $2"
                exit 1
            fi
            ;;
        delete)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 delete <name>"
                exit 1
            fi
            delete_parameter "$2"
            ;;
        list)
            list_parameters "$2"
            ;;
        setup)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 setup <environment>"
                exit 1
            fi
            setup_environment_parameters "$2"
            ;;
        cleanup)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 cleanup <environment>"
                exit 1
            fi
            read -p "Are you sure you want to delete all parameters for $2? (y/N): " confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                cleanup_environment_parameters "$2"
            else
                log_info "Operation cancelled"
            fi
            ;;
        backup)
            if [ $# -lt 3 ]; then
                log_error "Usage: $0 backup <environment> <file>"
                exit 1
            fi
            backup_parameters "$2" "$3"
            ;;
        restore)
            if [ $# -lt 3 ]; then
                log_error "Usage: $0 restore <environment> <file>"
                exit 1
            fi
            restore_parameters "$2" "$3"
            ;;
        -h|--help|help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Check prerequisites
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure'."
    exit 1
fi

# Run main function
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

main "$@"
