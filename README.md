# Hosting a Static Website on Google Cloud Platform

This repository contains code and configuration for deploying a secure, scalable static website on Google Cloud Platform.

## Overview

This project provides a complete solution for hosting static websites on GCP using Cloud Storage, Cloud CDN, and Cloud Load Balancing. The setup includes custom domain configuration, HTTPS support, and automated deployment through Cloud Build.

![Architecture Diagram](https://storage.googleapis.com/your-bucket/static-website-architecture.png)

## Features

- 📦 **Cost-effective storage** using Google Cloud Storage buckets
- 🔒 **Free SSL/TLS certificates** with automatic renewal
- 🚀 **Global content delivery** via Cloud CDN
- 🔄 **Continuous deployment** using Cloud Build
- 🛡️ **Security features** including custom headers and access control
- 📊 **Performance monitoring** with Cloud Monitoring

## Prerequisites

- Google Cloud Platform account
- Registered domain name
- `gcloud` CLI installed and configured
- Basic knowledge of HTML, CSS, and JavaScript

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/static-website-gcp.git
cd static-website-gcp
```

### 2. Configure the Project

Edit the `config.yaml` file to set your project-specific variables:

```yaml
project_id: "your-gcp-project-id"
domain_name: "yourdomain.com"
region: "us-central1"
website_sources: "./website"
```

### 3. Set Up Infrastructure Using Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 4. Deploy Your Website

Place your static website files in the `website` directory, then run:

```bash
./deploy.sh
```

### 5. Set Up DNS Records

After deployment, configure your domain's DNS records to point to the load balancer's IP address:

```
A @ [LOAD_BALANCER_IP_ADDRESS]
CNAME www [YOUR_DOMAIN]
```

## Detailed Setup Instructions

### Creating a Cloud Storage Bucket

```bash
gsutil mb -l us-central1 -b on gs://your-website-bucket
gsutil web set -m index.html -e 404.html gs://your-website-bucket
```

### Uploading Website Files

```bash
gsutil -m cp -r ./website/* gs://your-website-bucket
gsutil iam ch allUsers:objectViewer gs://your-website-bucket
```

### Setting Up Load Balancing and CDN

1. Create a load balancer with HTTPS
2. Configure a backend bucket
3. Set up Cloud CDN
4. Request an SSL certificate

See `docs/load-balancer-setup.md` for detailed instructions.

### Automating Deployments

Set up a Cloud Build trigger to automatically deploy your website when changes are pushed to your repository:

```yaml
# cloudbuild.yaml
steps:
  - name: 'gcr.io/cloud-builders/gsutil'
    args: ['-m', 'cp', '-r', './website/*', 'gs://your-website-bucket']
```

## Terraform Configuration

This repository includes Terraform configurations for creating the entire infrastructure:

```hcl
# Main infrastructure setup
module "static_website" {
  source      = "./modules/static-website"
  project_id  = var.project_id
  domain_name = var.domain_name
  
  enable_cdn              = true
  create_ssl_certificate  = true
  enable_security_headers = true
  
  website_source_dir = "../website"
}
```

See the `terraform` directory for complete configuration files.

## Performance Optimization

- Enable browser caching with appropriate headers
- Compress static assets
- Optimize images using WebP format
- Configure custom caching strategies in Cloud CDN

## Security Considerations

- Secure resource permissions
- Set up appropriate firewall rules
- Configure security headers (HSTS, CSP, etc.)
- Implement Cloud Armor for additional security (optional)

## Monitoring and Analytics

Monitor your website's performance and usage with:

- Cloud Monitoring dashboards
- Cloud Logging for access logs
- Integration with Google Analytics

## Cost Optimization

Estimated monthly costs for a small to medium traffic website:

- Cloud Storage: ~$0.50
- Cloud CDN: ~$0.10 + data transfer
- Load Balancer: ~$18
- SSL Certificate: Free

See `docs/cost-optimization.md` for tips on reducing costs.

## Troubleshooting

Common issues and solutions:

- **404 errors**: Ensure index.html is properly configured
- **SSL issues**: Check certificate provisioning status
- **Deployment failures**: Verify permissions and build configuration

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
