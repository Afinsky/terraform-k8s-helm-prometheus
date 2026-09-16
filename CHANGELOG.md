# Changelog

All notable changes to this project will be documented in this file.

## [1.2.8](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.2.7...v1.2.8) (2026-09-16)


### Bug Fixes

* **security:** re-enable trivy scanning and remediate findings ([#22](https://github.com/Afinsky/terraform-k8s-helm-prometheus/issues/22)) ([d6a92d9](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/d6a92d963167fbbc17bdb4582a4b853fd23a823f))

## [1.2.7](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.2.6...v1.2.7) (2026-09-16)


### Bug Fixes

* **eks-workloads:** centralize app secrets in management account via cross-account assume-role ([f277f22](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/f277f220b13612fe29c93c2cdba38d17f1aa9d2d))

## [1.2.6](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.2.5...v1.2.6) (2026-09-16)


### Bug Fixes

* **eks-workloads:** correct external-dns Route53 assume-role flag and… ([#20](https://github.com/Afinsky/terraform-k8s-helm-prometheus/issues/20)) ([59877e8](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/59877e8105403c834a2b93225c72472995f3cff1))

## [1.2.5](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.2.4...v1.2.5) (2026-09-15)


### Bug Fixes

* split eks-cluster into eks-cluster + eks-workloads, align SSO naming, fix VPC DNS ([abd6093](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/abd6093976d6ce2589a1d8986a9b8ef7ae383b01))

## [1.2.4](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.2.3...v1.2.4) (2026-09-14)


### Bug Fixes

* layers reorganization ([#11](https://github.com/Afinsky/terraform-k8s-helm-prometheus/issues/11)) ([6c162d8](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/6c162d896010d543a25a8679615fefe2534619d0))

## [1.2.3](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.2.2...v1.2.3) (2026-09-14)


### Bug Fixes

* small improvements ([#10](https://github.com/Afinsky/terraform-k8s-helm-prometheus/issues/10)) ([58640b1](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/58640b16bc7de44bcc50501d4509d350f8b47955))

## [1.2.2](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.2.1...v1.2.2) (2026-09-14)


### Bug Fixes

* reorganiza organization + new account as a member ([#9](https://github.com/Afinsky/terraform-k8s-helm-prometheus/issues/9)) ([8740de1](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/8740de1935c0c220beed8555e03999e49bcc9f2d))

## [1.2.1](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.2.0...v1.2.1) (2026-09-13)


### Bug Fixes

* reorganize using Terragrunt - remove unused bootstrap, instead use native terragrunt bootstrap ([1761daa](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/1761daa14e6baf84d044bbe84072526b07d07bf6))

## [1.2.0](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.1.1...v1.2.0) (2026-09-13)

## [1.1.1](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.1.0...v1.1.1) (2026-09-11)


### Bug Fixes

* Feat/OIDC 2 ([#5](https://github.com/Afinsky/terraform-k8s-helm-prometheus/issues/5)) ([40fd0b4](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/40fd0b4d32b1f75ca8ab60caa561c8c785779b18))

## [1.1.0](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.0.1...v1.1.0) (2026-09-11)

## [1.0.1](https://github.com/Afinsky/terraform-k8s-helm-prometheus/compare/v1.0.0...v1.0.1) (2026-09-01)


### Bug Fixes

* fixed namespace issue + added redirect from http to https in ngi… ([#3](https://github.com/Afinsky/terraform-k8s-helm-prometheus/issues/3)) ([c5621f7](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/c5621f78d44b210b1396d729fb30c3cec602b9c8))

## 1.0.0 (2026-08-27)


### Features

* initial setup ([25ad28b](https://github.com/Afinsky/terraform-k8s-helm-prometheus/commit/25ad28bcf4ceb40539a712c470c6798ca168b6f8))
