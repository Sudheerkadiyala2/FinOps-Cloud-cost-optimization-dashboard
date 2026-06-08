# Contributing to AWS Cost Intelligence Platform

Thank you for your interest in contributing to the AWS Cost Intelligence Platform.

This project aims to build a real-world cloud governance and FinOps platform that helps organizations:

* identify cloud waste
* improve cloud visibility
* generate cost optimization insights
* automate governance workflows

We welcome contributors interested in:

* frontend engineering
* cloud engineering
* DevOps
* infrastructure automation
* FinOps
* observability
* developer experience

---

# Project Vision

This is NOT a tutorial-only AWS project.

The goal is to simulate production-inspired cloud engineering practices using:

* serverless architecture
* event-driven workflows
* infrastructure automation
* CI/CD
* governance analytics

The platform is intentionally designed to evolve collaboratively.

---

# Learning & Collaboration

I am open to learning from anyone contributing to this project.

Whether you are:

* a beginner
* an experienced engineer
* a frontend developer
* a DevOps engineer
* a cloud architect

your ideas, suggestions, and improvements are always welcome.

The purpose of this project is not only to build a platform, but also to learn real-world engineering practices collaboratively.

---

# Tech Stack

## AWS Services

* Lambda
* API Gateway
* S3
* DynamoDB
* EventBridge
* CloudWatch
* IAM

## Languages & Tools

* Python
* boto3
* GitHub Actions
* Terraform (planned)

## Frontend (Contributor Scope)

Frontend contributors may use:

* React
* Angular
* Tailwind CSS
* Recharts
* TypeScript

---

# Repository Structure

```text
aws-cost-intelligence/
├── lambdas/
│   ├── cost_collector/
│   ├── waste_detector/
│   ├── api/
│   └── notifier/
│
├── terraform/
├── frontend/
├── mock/
├── docs/
├── .github/
│   └── workflows/
│
├── docker-compose.yml
├── README.md
└── CONTRIBUTING.md
```

---

# Current Backend Features

Implemented:

* AWS resource inventory collection
* S3 raw storage
* waste detection engine
* DynamoDB findings storage
* API Gateway endpoints
* EventBridge automation
* GitHub Actions CI/CD

Current detection capabilities:

* unused Elastic IPs
* unattached EBS volumes
* idle EC2 instances

---

# Contributor Areas

## Frontend Contributors

Suggested frontend features:

* findings dashboard
* KPI summary cards
* trends charts
* governance tables
* filtering/search
* analytics visualizations

Frontend contributors should primarily work inside:

```text
frontend/
```

---

## DevOps / Cloud Contributors

Suggested tasks:

* Terraform modules
* GitHub Actions improvements
* logging improvements
* monitoring
* API enhancements
* deployment automation

---

# Getting Started

## 1. Fork Repository

Fork the repository into your GitHub account.

---

## 2. Clone Repository

```bash
git clone <your-fork-url>
cd aws-cost-intelligence
```

---

## 3. Create Branch

Please create feature-specific branches.

Example:

```bash
git checkout -b feature/frontend-dashboard
```

Avoid committing directly to:

```text
main
```

---

# Branch Naming Convention

Recommended branch naming:

| Type     | Example               |
| -------- | --------------------- |
| feature  | feature/trends-chart  |
| fix      | fix/api-response      |
| docs     | docs/readme-update    |
| refactor | refactor/shared-utils |

---

# Pull Request Guidelines

Before creating a PR:

Please ensure:

* code is tested
* changes are documented
* naming is clean and consistent
* APIs remain stable
* unnecessary dependencies are avoided

---

# Pull Request Title Examples

```text
feat: add findings dashboard

fix: resolve trends API parsing issue

docs: improve architecture documentation
```

---

# Coding Guidelines

## Backend

* use meaningful variable names
* avoid hardcoded values
* add error handling
* use structured logging where possible

## Frontend

* keep components modular
* use reusable UI patterns
* avoid large monolithic files

---

# API Stability

Frontend contributors rely on stable API contracts.

Please avoid changing:

* response field names
* response nesting
* endpoint paths

without discussion.

---

# Mock Data

Mock JSON responses are available inside:

```text
mock/
```

Frontend contributors are encouraged to use mock data during development instead of depending on live AWS APIs.

---

# CI/CD

GitHub Actions automatically deploy Lambda functions on push to:

```text
main
```

Please avoid pushing unstable code directly to:

```text
main
```

---

# Planned Future Enhancements

Planned future features include:

* Terraform infrastructure provisioning
* Athena analytics
* Slack notifications
* anomaly detection
* governance recommendations
* historical analytics
* multi-account support

---

# Code of Conduct

Please:

* be respectful
* provide constructive feedback
* collaborate professionally
* help improve engineering quality

---

# Reporting Issues

If you encounter:

* bugs
* API inconsistencies
* deployment issues
* documentation gaps

please create a GitHub Issue with:

* reproduction steps
* logs/screenshots if applicable
* expected behavior

---

# Contribution Philosophy

This project values:

* practical engineering
* clean architecture
* automation
* cloud-native design
* collaborative learning

The goal is to build something that reflects real-world cloud engineering and FinOps practices.

---

# Maintainer

Sudheer Kumar Kadiyala

Cloud / DevOps Engineer Learner

Focused on:

* Cloud Engineering
* DevOps
* Platform Engineering
* FinOps
* AI Infrastructure

