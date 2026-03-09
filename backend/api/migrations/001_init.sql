-- Multiplayer schema scaffold (v1 draft)
-- Run manually on MySQL 8+.

CREATE TABLE IF NOT EXISTS accounts (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  account_uid CHAR(26) NOT NULL UNIQUE,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  verified TINYINT(1) NOT NULL DEFAULT 0,
  public_name VARCHAR(80) DEFAULT NULL,
  wants_news TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);

CREATE TABLE IF NOT EXISTS account_verifications (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  account_id BIGINT UNSIGNED NOT NULL,
  code_hash VARCHAR(255) NOT NULL,
  expires_at DATETIME NOT NULL,
  used_at DATETIME DEFAULT NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE TABLE IF NOT EXISTS account_sessions (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  account_id BIGINT UNSIGNED NOT NULL,
  session_token_hash VARCHAR(255) NOT NULL UNIQUE,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME DEFAULT NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id)
);

CREATE TABLE IF NOT EXISTS admin_sessions (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(80) NOT NULL,
  session_token_hash VARCHAR(255) NOT NULL UNIQUE,
  expires_at DATETIME NOT NULL,
  revoked_at DATETIME DEFAULT NULL,
  created_at DATETIME NOT NULL
);

CREATE TABLE IF NOT EXISTS realms (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  realm_uid VARCHAR(64) NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  status ENUM('active','coming_soon','disabled') NOT NULL DEFAULT 'active',
  supports_guilds TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL
);

CREATE TABLE IF NOT EXISTS characters (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  character_uid CHAR(26) NOT NULL UNIQUE,
  account_id BIGINT UNSIGNED NOT NULL,
  realm_id BIGINT UNSIGNED NOT NULL,
  local_character_uuid CHAR(36) DEFAULT NULL,
  name VARCHAR(120) NOT NULL,
  race VARCHAR(80) NOT NULL,
  class_name VARCHAR(80) NOT NULL,
  network_mode ENUM('online') NOT NULL DEFAULT 'online',
  seed VARCHAR(128) DEFAULT NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (account_id) REFERENCES accounts(id),
  FOREIGN KEY (realm_id) REFERENCES realms(id)
);

CREATE TABLE IF NOT EXISTS guilds (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  guild_uid CHAR(26) NOT NULL UNIQUE,
  realm_id BIGINT UNSIGNED NOT NULL,
  formal_name VARCHAR(160) NOT NULL,
  short_tag VARCHAR(24) NOT NULL,
  alignment_code VARCHAR(40) NOT NULL,
  type_code VARCHAR(40) NOT NULL,
  motto VARCHAR(255) DEFAULT NULL,
  chief_character_id BIGINT UNSIGNED NOT NULL,
  immutable_on_membership TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (realm_id) REFERENCES realms(id),
  FOREIGN KEY (chief_character_id) REFERENCES characters(id),
  UNIQUE KEY uq_guild_name_realm (realm_id, formal_name),
  UNIQUE KEY uq_guild_tag_realm (realm_id, short_tag)
);

CREATE TABLE IF NOT EXISTS guild_rules (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  guild_id BIGINT UNSIGNED NOT NULL UNIQUE,
  majority_type ENUM('functional_50','three_fifths_60','two_thirds_66_7','three_fourths_75') NOT NULL,
  majority_basis ENUM('absolute','present') NOT NULL,
  quorum_enabled TINYINT(1) NOT NULL DEFAULT 0,
  quorum_percent TINYINT UNSIGNED DEFAULT NULL,
  no_confidence_enabled TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (guild_id) REFERENCES guilds(id)
);

CREATE TABLE IF NOT EXISTS guild_members (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  guild_id BIGINT UNSIGNED NOT NULL,
  character_id BIGINT UNSIGNED NOT NULL,
  role ENUM('chief','member') NOT NULL DEFAULT 'member',
  status ENUM('active','left','kicked') NOT NULL DEFAULT 'active',
  joined_at DATETIME NOT NULL,
  left_at DATETIME DEFAULT NULL,
  FOREIGN KEY (guild_id) REFERENCES guilds(id),
  FOREIGN KEY (character_id) REFERENCES characters(id),
  UNIQUE KEY uq_guild_character (guild_id, character_id)
);

CREATE TABLE IF NOT EXISTS guild_presence (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  guild_id BIGINT UNSIGNED NOT NULL,
  character_id BIGINT UNSIGNED NOT NULL,
  present TINYINT(1) NOT NULL,
  updated_at DATETIME NOT NULL,
  expires_at DATETIME NOT NULL,
  FOREIGN KEY (guild_id) REFERENCES guilds(id),
  FOREIGN KEY (character_id) REFERENCES characters(id),
  UNIQUE KEY uq_presence (guild_id, character_id)
);

CREATE TABLE IF NOT EXISTS guild_motions (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  motion_uid CHAR(26) NOT NULL UNIQUE,
  guild_id BIGINT UNSIGNED NOT NULL,
  proposer_character_id BIGINT UNSIGNED NOT NULL,
  motion_type VARCHAR(64) NOT NULL,
  title VARCHAR(200) NOT NULL,
  payload_json JSON DEFAULT NULL,
  state ENUM('proposed','discussion','voting_open','passed','failed','applied') NOT NULL,
  opens_at DATETIME NOT NULL,
  closes_at DATETIME NOT NULL,
  result_applied_at DATETIME DEFAULT NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  FOREIGN KEY (guild_id) REFERENCES guilds(id),
  FOREIGN KEY (proposer_character_id) REFERENCES characters(id)
);

CREATE TABLE IF NOT EXISTS guild_votes (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  motion_id BIGINT UNSIGNED NOT NULL,
  voter_character_id BIGINT UNSIGNED NOT NULL,
  choice ENUM('yes','no','abstain') NOT NULL,
  voted_at DATETIME NOT NULL,
  FOREIGN KEY (motion_id) REFERENCES guild_motions(id),
  FOREIGN KEY (voter_character_id) REFERENCES characters(id),
  UNIQUE KEY uq_motion_voter (motion_id, voter_character_id)
);

CREATE TABLE IF NOT EXISTS guild_logs (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  guild_id BIGINT UNSIGNED NOT NULL,
  log_type ENUM('system','governance','procedural') NOT NULL,
  message TEXT NOT NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (guild_id) REFERENCES guilds(id)
);

CREATE TABLE IF NOT EXISTS character_checkins (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  checkin_uid CHAR(26) NOT NULL UNIQUE,
  character_id BIGINT UNSIGNED NOT NULL,
  sent_at DATETIME NOT NULL,
  runtime_seconds_delta INT UNSIGNED NOT NULL,
  snapshot_json JSON NOT NULL,
  accepted TINYINT(1) NOT NULL,
  risk_state ENUM('green','yellow','red') NOT NULL,
  created_at DATETIME NOT NULL,
  FOREIGN KEY (character_id) REFERENCES characters(id)
);

CREATE TABLE IF NOT EXISTS checkin_flags (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  checkin_id BIGINT UNSIGNED NOT NULL,
  flag_code VARCHAR(80) NOT NULL,
  severity ENUM('low','medium','high') NOT NULL,
  reviewed TINYINT(1) NOT NULL DEFAULT 0,
  review_note TEXT DEFAULT NULL,
  created_at DATETIME NOT NULL,
  reviewed_at DATETIME DEFAULT NULL,
  FOREIGN KEY (checkin_id) REFERENCES character_checkins(id)
);

CREATE INDEX idx_accounts_email_verified ON accounts (email, verified);
CREATE INDEX idx_guild_members_guild_status ON guild_members (guild_id, status);
CREATE INDEX idx_guild_logs_guild_created ON guild_logs (guild_id, created_at);
