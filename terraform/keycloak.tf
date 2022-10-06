locals {
  user_list   = concat(var.reader_list, var.author_list, var.admin_list)
}

provider "keycloak" {
  client_id     = var.kc_terraform_auth_client_id
  client_secret = var.kc_terraform_auth_client_password
  url           = var.kc_base_url
  realm         = var.kc_realm
}

# Get Unique ID in keycloak
data "keycloak_realm" "realm" {
  realm    = var.kc_realm
}

data "keycloak_openid_client" "realm_management" {
  realm_id  = var.kc_realm
  client_id = var.kc_openid_client_id
}

data "keycloak_user" "this" {
  for_each = toset(local.user_list)
  realm_id = data.keycloak_realm.realm.id
  username = each.key
}


## Creation of the roles
resource "keycloak_role" "reader_role" {
  realm_id  = data.keycloak_realm.realm.id
  client_id = data.keycloak_openid_client.realm_management.id
  name        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:saml-provider/BCGovKeyCloak-${var.kc_realm},${aws_iam_role.quicksight_reader_role.arn}"
  description = "Readers Role access for Quicksight"
}

resource "keycloak_role" "author_role" {
  realm_id  = data.keycloak_realm.realm.id
  client_id = data.keycloak_openid_client.realm_management.id
  name        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:saml-provider/BCGovKeyCloak-${var.kc_realm},${aws_iam_role.quicksight_author_role.arn}"
  description = "Author access for Quicksight"
}

resource "keycloak_role" "admin_role" {
  realm_id  = data.keycloak_realm.realm.id
  client_id = data.keycloak_openid_client.realm_management.id
  name        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:saml-provider/BCGovKeyCloak-${var.kc_realm},${aws_iam_role.quicksight_admin_role.arn}"
  description = "Admin access for Quicksight"
}


## Creation of the groups
resource "keycloak_group" "reader_group" {
  realm_id = data.keycloak_realm.realm.id
  name     = "QuicksightReader"
}

resource "keycloak_group" "author_group" {
  realm_id = data.keycloak_realm.realm.id
  name     = "QuicksightAuthor"
}

resource "keycloak_group" "admin_group" {
  realm_id = data.keycloak_realm.realm.id
  name     = "QuicksightAdmin"
}

# Link group with roles
resource "keycloak_group_roles" "reader_group_roles" {
  realm_id = data.keycloak_realm.realm.id
  group_id = keycloak_group.reader_group.id

  role_ids = [
    keycloak_role.reader_role.id
  ]
}

resource "keycloak_group_roles" "author_group_roles" {
  realm_id = data.keycloak_realm.realm.id
  group_id = keycloak_group.author_group.id

  role_ids = [
    keycloak_role.author_role.id
  ]
}

resource "keycloak_group_roles" "admin_group_roles" {
  realm_id = data.keycloak_realm.realm.id
  group_id = keycloak_group.admin_group.id

  role_ids = [
    keycloak_role.admin_role.id
  ]
}

# Link groups with users
resource "keycloak_user_groups" "reader_groups_association" {
  for_each   = toset(var.reader_list)
  realm_id   = data.keycloak_realm.realm.id
  user_id    = data.keycloak_user.this[each.key].id
  exhaustive = false

  group_ids = [
    keycloak_group.reader_group.id
  ]
}

resource "keycloak_user_groups" "author_groups_association" {
  for_each   = toset(var.author_list)
  realm_id   = data.keycloak_realm.realm.id
  user_id    = data.keycloak_user.this[each.key].id
  exhaustive = false

  group_ids = [
    keycloak_group.author_group.id
  ]
}

resource "keycloak_user_groups" "admin_groups_association" {
  for_each   = toset(var.admin_list)
  realm_id   = data.keycloak_realm.realm.id
  user_id    = data.keycloak_user.this[each.key].id
  exhaustive = false

  group_ids = [
    keycloak_group.admin_group.id
  ]
}
