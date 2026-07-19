CREATE TABLE IF NOT EXISTS `lime_redzones` (
  `id` INT NOT NULL PRIMARY KEY,
  `data` LONGTEXT
);

INSERT IGNORE INTO `lime_redzones` (`id`, `data`) VALUES (1, '{}');

CREATE TABLE IF NOT EXISTS `lime_redzones_logs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `category` VARCHAR(32) NOT NULL,
    `title` VARCHAR(120) NOT NULL,
    `description` TEXT,
    `actor` VARCHAR(120),
    `fields` TEXT,
    `created_at` INT NOT NULL,
    INDEX `idx_cat_time` (`category`, `created_at`)
);
