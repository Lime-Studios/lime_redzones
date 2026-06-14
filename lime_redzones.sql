CREATE TABLE IF NOT EXISTS `lime_redzones` (
  `id` INT NOT NULL PRIMARY KEY,
  `data` LONGTEXT
);

INSERT IGNORE INTO `lime_redzones` (`id`, `data`) VALUES (1, '{}');
