.PHONY: init plan apply destroy fmt validate

init:
	./setup.sh

plan:
	terraform plan

apply:
	./script.sh

destroy:
	terraform destroy -auto-approve

fmt:
	terraform fmt -recursive

validate:
	terraform validate
