$ErrorActionPreference = 'Stop'
$pattern = '(?i)overseas-roster-template-optimization|guanghuo-wage-register-audit|worker-service|glm-system-test|31cc73b|b4bdb667'

if ('system-test service <business-service>' -match $pattern) {
    throw 'Expected generic system-test wording to pass the distributable-surface policy.'
}
if ('worker-service' -notmatch $pattern) {
    throw 'Expected a requirement-specific service identifier to be rejected.'
}
if ('31cc73b' -notmatch $pattern) {
    throw 'Expected a historical revision identifier to be rejected.'
}

Write-Output 'distributable-surface positive and case-leak negative cases passed.'
