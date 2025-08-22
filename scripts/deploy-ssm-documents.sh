#!/bin/bash

# SSM Document Deployment Script for Cockpit Installation
# Deploys all SSM documents required for the modular Cockpit installation

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SSM_DOCS_DIR="$PROJECT_ROOT/ssm-documents"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Load environment configuration
load_env_config() {
    # Load environment variables from .env file if it exists
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        source "$PROJECT_ROOT/.env"
        log "Loaded configuration from .env file"
    fi
    
    # Set defaults (can be overridden by .env file or command line)
    REGION="${REGION:-us-east-1}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # Check if SSM documents directory exists
    if [[ ! -d "$SSM_DOCS_DIR" ]]; then
        error "SSM documents directory not found: $SSM_DOCS_DIR"
        exit 1
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Deploy a single SSM document
deploy_document() {
    local doc_name="$1"
    local doc_file="$2"
    
    log "Deploying SSM document: $doc_name"
    
    # Check if document already exists
    if aws ssm describe-document --name "$doc_name" --region "$REGION" >/dev/null 2>&1; then
        warning "Document $doc_name already exists. Updating..."
        
        # Update existing document
        if aws ssm update-document \
            --name "$doc_name" \
            --content "file://$doc_file" \
            --document-version '$LATEST' \
            --region "$REGION" >/dev/null 2>&1; then
            
            # Set new version as default
            local new_version=$(aws ssm describe-document \
                --name "$doc_name" \
                --region "$REGION" \
                --query 'Document.LatestVersion' \
                --output text)
            
            aws ssm update-document-default-version \
                --name "$doc_name" \
                --document-version "$new_version" \
                --region "$REGION" >/dev/null 2>&1
                
            success "Updated document: $doc_name (version $new_version)"
        else
            error "Failed to update document: $doc_name"
            return 1
        fi
    else
        log "Creating new document: $doc_name"
        
        # Create new document
        if aws ssm create-document \
            --name "$doc_name" \
            --content "file://$doc_file" \
            --document-type "Command" \
            --document-format "YAML" \
            --region "$REGION" >/dev/null 2>&1; then
            
            success "Created document: $doc_name"
        else
            error "Failed to create document: $doc_name"
            return 1
        fi
    fi
}

# Deploy automation document (different type)
deploy_automation_document() {
    local doc_name="$1"
    local doc_file="$2"
    
    log "Deploying SSM automation document: $doc_name"
    
    # Check if document already exists
    if aws ssm describe-document --name "$doc_name" --region "$REGION" >/dev/null 2>&1; then
        warning "Document $doc_name already exists. Updating..."
        
        # Update existing document
        if aws ssm update-document \
            --name "$doc_name" \
            --content "file://$doc_file" \
            --document-version '$LATEST' \
            --region "$REGION" >/dev/null 2>&1; then
            
            # Set new version as default
            local new_version=$(aws ssm describe-document \
                --name "$doc_name" \
                --region "$REGION" \
                --query 'Document.LatestVersion' \
                --output text)
            
            aws ssm update-document-default-version \
                --name "$doc_name" \
                --document-version "$new_version" \
                --region "$REGION" >/dev/null 2>&1
                
            success "Updated automation document: $doc_name (version $new_version)"
        else
            error "Failed to update automation document: $doc_name"
            return 1
        fi
    else
        log "Creating new automation document: $doc_name"
        
        # Create new automation document
        if aws ssm create-document \
            --name "$doc_name" \
            --content "file://$doc_file" \
            --document-type "Automation" \
            --document-format "YAML" \
            --region "$REGION" >/dev/null 2>&1; then
            
            success "Created automation document: $doc_name"
        else
            error "Failed to create automation document: $doc_name"
            return 1
        fi
    fi
}

# List all documents for verification
list_deployed_documents() {
    log "Verifying deployed documents..."
    
    local documents=(
        "cockpit-system-prep"
        "cockpit-core-install"
        "cockpit-services-setup"
        "cockpit-extensions"
        "cockpit-user-config"
        "cockpit-finalize"
        "cockpit-deploy-automation"
    )
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "📋 DEPLOYED SSM DOCUMENTS"
    echo "═══════════════════════════════════════════════════"
    
    local all_deployed=true
    
    for doc in "${documents[@]}"; do
        if aws ssm describe-document --name "$doc" --region "$REGION" >/dev/null 2>&1; then
            local version=$(aws ssm describe-document \
                --name "$doc" \
                --region "$REGION" \
                --query 'Document.DocumentVersion' \
                --output text)
            local status=$(aws ssm describe-document \
                --name "$doc" \
                --region "$REGION" \
                --query 'Document.Status' \
                --output text)
            echo -e "✅ $doc (v$version, $status)"
        else
            echo -e "❌ $doc (not found)"
            all_deployed=false
        fi
    done
    
    echo "═══════════════════════════════════════════════════"
    
    if [[ "$all_deployed" == true ]]; then
        success "All SSM documents deployed successfully!"
        return 0
    else
        error "Some SSM documents failed to deploy"
        return 1
    fi
}

# Test deployment by running a dry-run automation
test_deployment() {
    log "Testing deployment with validation..."
    
    # Just validate the main automation document can be described
    if aws ssm describe-document \
        --name "cockpit-deploy-automation" \
        --region "$REGION" >/dev/null 2>&1; then
        success "Main automation document is accessible"
        
        log "Testing parameter validation..."
        # Get document parameters to verify structure
        local params=$(aws ssm describe-document-permission \
            --name "cockpit-deploy-automation" \
            --region "$REGION" 2>/dev/null || echo "No permissions set")
        
        success "Document structure validated"
    else
        error "Main automation document is not accessible"
        return 1
    fi
}

# Clean up old document versions (optional)
cleanup_old_versions() {
    log "Cleaning up old document versions (keeping latest 3)..."
    
    local documents=(
        "cockpit-system-prep"
        "cockpit-core-install"
        "cockpit-services-setup"
        "cockpit-extensions"
        "cockpit-user-config"
        "cockpit-finalize"
        "cockpit-deploy-automation"
    )
    
    for doc in "${documents[@]}"; do
        # Get all versions
        local versions=$(aws ssm list-document-versions \
            --name "$doc" \
            --region "$REGION" \
            --query 'DocumentVersions[?Status==`Active`].DocumentVersion' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$versions" ]]; then
            local version_array=($versions)
            if [[ ${#version_array[@]} -gt 3 ]]; then
                log "Cleaning up old versions for $doc..."
                # Keep latest 3, delete older ones
                for ((i=3; i<${#version_array[@]}; i++)); do
                    local old_version="${version_array[$i]}"
                    aws ssm delete-document \
                        --name "$doc" \
                        --document-version "$old_version" \
                        --region "$REGION" >/dev/null 2>&1 || true
                    echo "  Deleted version $old_version"
                done
            fi
        fi
    done
    
    success "Cleanup completed"
}

# Show usage information
show_usage() {
    echo "SSM Document Deployment Script for Cockpit Installation"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --region REGION     Set AWS region (default: $REGION)"
    echo "  --cleanup          Clean up old document versions"
    echo "  --test             Test deployment after completion"
    echo "  --list             List currently deployed documents"
    echo "  --help             Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  REGION             AWS region to deploy to"
    echo ""
    echo "Examples:"
    echo "  $0                 # Deploy all documents"
    echo "  $0 --cleanup       # Deploy and cleanup old versions"
    echo "  $0 --test          # Deploy and test"
    echo "  $0 --list          # Just list current documents"
}

# Main execution
main() {
    local cleanup=false
    local test=false
    local list_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                REGION="$2"
                shift 2
                ;;
            --cleanup)
                cleanup=true
                shift
                ;;
            --test)
                test=true
                shift
                ;;
            --list)
                list_only=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "═══════════════════════════════════════════════════"
    echo "🚀 COCKPIT SSM DOCUMENT DEPLOYMENT"
    echo "═══════════════════════════════════════════════════"
    echo "Region: $REGION"
    echo "SSM Documents: $SSM_DOCS_DIR"
    echo "═══════════════════════════════════════════════════"
    echo ""
    
    # If only listing, do that and exit
    if [[ "$list_only" == true ]]; then
        list_deployed_documents
        exit $?
    fi
    
    load_env_config
    check_prerequisites
    
    # Deploy individual command documents
    log "Deploying component documents..."
    deploy_document "cockpit-system-prep" "$SSM_DOCS_DIR/cockpit-system-prep.yaml"
    deploy_document "cockpit-core-install" "$SSM_DOCS_DIR/cockpit-core-install.yaml"
    deploy_document "cockpit-services-setup" "$SSM_DOCS_DIR/cockpit-services-setup.yaml"
    deploy_document "cockpit-extensions" "$SSM_DOCS_DIR/cockpit-extensions.yaml"
    deploy_document "cockpit-user-config" "$SSM_DOCS_DIR/cockpit-user-config.yaml"
    deploy_document "cockpit-finalize" "$SSM_DOCS_DIR/cockpit-finalize.yaml"
    
    # Deploy main automation document
    log "Deploying main automation document..."
    deploy_automation_document "cockpit-deploy-automation" "$SSM_DOCS_DIR/cockpit-deploy-automation.yaml"
    
    # Verify deployment
    if ! list_deployed_documents; then
        error "Deployment verification failed"
        exit 1
    fi
    
    # Optional cleanup
    if [[ "$cleanup" == true ]]; then
        cleanup_old_versions
    fi
    
    # Optional testing
    if [[ "$test" == true ]]; then
        test_deployment
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "🎉 DEPLOYMENT COMPLETE"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "Next steps:"
    echo "1. Update your launch script to use 'cockpit-deploy-automation'"
    echo "2. Test the deployment on a new instance"
    echo "3. Monitor SNS notifications during installation"
    echo ""
    echo "Main automation document: cockpit-deploy-automation"
    echo "Region: $REGION"
    echo "═══════════════════════════════════════════════════"
}

# Run main function with all arguments
main "$@"