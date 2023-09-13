#!/bin/bash

function show_login_and_env_var_message() {
    echo -e "\e[34mMake sure you are logged in Azure CLI and ACR, and set necessary environment variables.\e[0m"
    cat << EOF
If not, you need to create .env following README.md and run 'source .env'.
EOF
}

function check_login_and_env_vars() {
    # Check if you are logged in to Azure account.
    # TODO: This is not a perfect way because the token might be expired.
    if ! az account show > /dev/null 2>&1; then
        echo -e "\e[31mYou are not logged in to Azure.\e[0m"
        show_login_and_env_var_message
        exit 1
    fi

    if ! [ -n "$AZ_SUBSCRIPTION" ]; then
        echo -e "\e[31mVariable AZ_SUBSCRIPTION is not set.\e[0m"
        show_login_and_env_var_message
        exit 1
    fi

    if ! [ -n "$ACR_REGISTRY_NAME" ]; then
        echo -e "\e[31mVariable ACR_REGISTRY_NAME is not set.\e[0m"
        show_login_and_env_var_message
        exit 1
    fi

    if ! [ -n "$AZ_STORAGE_ACCOUNT" ]; then
        echo -e "\e[31mVariable AZ_STORAGE_ACCOUNT is not set.\e[0m"
        show_login_and_env_var_message
        exit 1
    fi

    if ! [ -n "$RESOURCE_GROUP" ]; then
        echo -e "\e[31mVariable RESOURCE_GROUP is not set.\e[0m"
        show_login_and_env_var_message
        exit 1
    fi

    if [ "$REUSE_AKS" != "true" ]; then
        if az group show --name "$RESOURCE_GROUP" > /dev/null; then
            echo -e "\e[31mResource group $RESOURCE_GROUP already exist in your subscription.\e[0m"
            exit 1
        fi
    fi
}

function show_need_to_run_setup_message() {
    echo -e "\e[31mYou need to run \`make setup\` in the project root before running this command/script.\e[0m"
}

# Only minimul check
# we can improve it if it's necessary
function check_install() {
    # Check `az` command is installed
    if ! command -v az &> /dev/null; then
        show_need_to_run_setup_message
        exit 1
    fi

    # Check `kubectl` command is installed
    if ! command -v kubectl &> /dev/null; then
        show_need_to_run_setup_message
        exit 1
    fi
}

