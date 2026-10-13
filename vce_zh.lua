-- VCE Maths toolkit (standalone document, 中英双语 Chinese + English)
-- Working steps stay in English; interface, hints and terms are bilingual.
-- Only this document loads the Chinese text (apps/vce/i18n_zh.lua).
platform.apiLevel = '2.4'
-- luacheck: ignore platform

require('apps.vce.i18n').install(require('apps.vce.i18n_zh'))
require('apps.vce.entry')('bi')
