.PHONY: all preflight-check setup test delete-rg


LOG_DIR=$(shell ./cmd/set-log-directory.sh)

all: test

preflight-check:
	@echo "Running preflight check..."
	@./cmd/run-preflight-check.sh

setup:
	@echo "Running setup script..."
	@./cmd/setup.sh

test:
	@echo "Running test..."
	@echo "stdout log is avaiable at $(LOG_DIR)/make-test.log"
	@mkdir -p $(LOG_DIR)
	@LOG_DIR=$(LOG_DIR) ./cmd/test.sh 2>&1 | tee $(LOG_DIR)/make-test.log

delete-rg:
	@echo "Deleting resource group $(RESOURCE_GROUP)"
	@az group delete -n $(RESOURCE_GROUP)