#!/usr/bin/env node
/**
 * Flow Skill 静态验证脚本
 * 检查命令文件 frontmatter、模板语法、command↔skill stub、lease 词法、scripts 路径。
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const COMMANDS_DIR = path.join(ROOT, '.claude', 'commands', 'flow');
const SKILLS_DIR = path.join(ROOT, '.claude', 'skills');
const TEMPLATES_DIR = path.join(ROOT, 'flow', 'templates');
const SCRIPTS_DIR = path.join(ROOT, 'flow', 'scripts');
const FLOW_DOCS_DIR = path.join(ROOT, 'flow', 'docs');

const REQUIRED_FRONTMATTER = ['name', 'description', 'category', 'tags', 'version'];
const REQUIRED_SCRIPTS = [
  'validate-domain-artifact.ps1',
  'validate-test-artifacts.ps1',
  'validate-test-cases.ps1',
  'test-scope-guard.ps1',
  'flow-test-controller.ps1',
];
const REQUIRED_DOCS = ['control-plane.md', 'schema.md', 'test-controller.md'];
const LEASE_MARKERS = [
  'REVIEW_REQUEST',
  'REVIEW_RESULT',
  'REPORT_REQUEST',
  'REPORT_LEASE_GRANTED',
];
const FORBIDDEN_CODEX_TOKENS = [
  'flow-codex-',
  '$flow-codex',
  'openai.yaml',
];

let errors = 0;
let warnings = 0;

function error(msg) {
  console.error(`  [ERROR] ${msg}`);
  errors++;
}

function warn(msg) {
  console.warn(`  [WARN]  ${msg}`);
  warnings++;
}

function ok(msg) {
  console.log(`  [OK]    ${msg}`);
}

function parseFrontmatter(filePath) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const match = content.match(/^---\s*\n([\s\S]*?)\n---\s*\n/);
  if (!match) return null;

  const yaml = match[1];
  const data = {};
  for (const line of yaml.split('\n')) {
    const idx = line.indexOf(':');
    if (idx === -1) continue;
    const key = line.slice(0, idx).trim();
    let val = line.slice(idx + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (val.startsWith('[') && val.endsWith(']')) {
      val = val.slice(1, -1).split(',').map(s => s.trim()).filter(Boolean);
    }
    data[key] = val;
  }
  return { data, content };
}

function validateCommands() {
  console.log('\n## 验证命令文件 (.claude/commands/flow/*.md)\n');
  const files = fs.readdirSync(COMMANDS_DIR).filter(f => f.endsWith('.md'));

  for (const file of files) {
    const filePath = path.join(COMMANDS_DIR, file);
    const result = parseFrontmatter(filePath);

    if (!result) {
      error(`${file}: 缺少 YAML frontmatter`);
      continue;
    }

    const { data, content } = result;
    let fileOk = true;

    for (const key of REQUIRED_FRONTMATTER) {
      if (!(key in data) || data[key] === '' || data[key] == null) {
        error(`${file}: frontmatter 缺少必填字段 "${key}"`);
        fileOk = false;
      }
    }

    if (data.tags && !Array.isArray(data.tags)) {
      warn(`${file}: tags 应为数组格式`);
      fileOk = false;
    }

    for (const tok of FORBIDDEN_CODEX_TOKENS) {
      if (content.includes(tok) && file !== 'test-design.md') {
        // test-design may mention Codex skill name as对照 — warn only for hard host tokens
        if (tok === 'openai.yaml' || tok === '$flow-codex') {
          error(`${file}: 禁止 Claude 包内出现 Codex 宿主 token "${tok}"`);
          fileOk = false;
        }
      }
    }

    if (fileOk) {
      ok(`${file}: frontmatter 完整`);
    }
  }
}

function validateSkillStubs() {
  console.log('\n## 验证 command ↔ skill stub 一致\n');
  if (!fs.existsSync(SKILLS_DIR)) {
    error('skills 目录不存在');
    return;
  }
  const commands = fs.readdirSync(COMMANDS_DIR).filter(f => f.endsWith('.md')).map(f => f.replace(/\.md$/, ''));
  const skillDirs = fs.readdirSync(SKILLS_DIR).filter(d => {
    const p = path.join(SKILLS_DIR, d);
    return fs.statSync(p).isDirectory() && d.startsWith('flow-');
  });

  for (const cmd of commands) {
    const skillName = `flow-${cmd}`;
    const skillPath = path.join(SKILLS_DIR, skillName, 'SKILL.md');
    if (!fs.existsSync(skillPath)) {
      error(`缺少 skill stub: ${skillName}/SKILL.md（对应 commands/flow/${cmd}.md）`);
      continue;
    }
    const body = fs.readFileSync(skillPath, 'utf-8');
    const lines = body.split(/\r?\n/).filter(l => l.trim().length > 0);
    // stub should be thin: allow frontmatter + short body
    if (lines.length > 40) {
      warn(`${skillName}/SKILL.md: 疑似双写正文（${lines.length} 非空行）；正文应只在 commands/flow/${cmd}.md`);
    }
    if (!body.includes(`/flow:${cmd}`) && !body.includes(`commands/flow/${cmd}.md`)) {
      warn(`${skillName}/SKILL.md: 未指向 /flow:${cmd} 或 commands/flow/${cmd}.md`);
    } else {
      ok(`${skillName} ↔ ${cmd}.md`);
    }
  }

  for (const d of skillDirs) {
    const cmd = d.replace(/^flow-/, '');
    if (!commands.includes(cmd)) {
      warn(`孤立 skill 目录 ${d}：无对应 commands/flow/${cmd}.md`);
    }
  }
}

function validateLeaseMarkers() {
  console.log('\n## 验证 lease 控制面词法\n');
  const mustHave = {
    'apply.md': ['REVIEW_REQUEST', 'REPORT_REQUEST'],
    'assign.md': ['REVIEW_REQUEST', 'REPORT_LEASE_GRANTED', 'REVIEW_RESULT'],
    'report.md': ['REPORT_LEASE_GRANTED', '[REPORT] complete'],
    'review.md': ['REVIEW_RESULT'],
  };
  for (const [file, markers] of Object.entries(mustHave)) {
    const p = path.join(COMMANDS_DIR, file);
    if (!fs.existsSync(p)) {
      error(`缺少 ${file}`);
      continue;
    }
    const c = fs.readFileSync(p, 'utf-8');
    let okFile = true;
    for (const m of markers) {
      if (!c.includes(m)) {
        error(`${file}: 缺少控制面标记 ${m}`);
        okFile = false;
      }
    }
    if (okFile) ok(`${file}: lease 标记齐全`);
  }

  const prompt = path.join(TEMPLATES_DIR, 'child-agent-prompt.md');
  if (fs.existsSync(prompt)) {
    const c = fs.readFileSync(prompt, 'utf-8');
    if (!c.includes('protocol_version') || !c.includes('lease-v1')) {
      error('child-agent-prompt.md: 须含 protocol_version / lease-v1 分支');
    } else {
      ok('child-agent-prompt.md: protocol 分支存在');
    }
  } else {
    error('缺少 flow/templates/child-agent-prompt.md');
  }
}

function validateSharedScripts() {
  console.log('\n## 验证 flow/scripts 与 flow/docs\n');
  for (const name of REQUIRED_SCRIPTS) {
    const p = path.join(SCRIPTS_DIR, name);
    if (!fs.existsSync(p)) {
      error(`缺少共享脚本 flow/scripts/${name}`);
      continue;
    }
    const head = fs.readFileSync(p, 'utf-8').split(/\r?\n/).slice(0, 5).join('\n');
    if (/^# Shim/m.test(head)) {
      error(`flow/scripts/${name} 不得为 shim`);
    } else {
      ok(`flow/scripts/${name}`);
    }
  }
  for (const name of REQUIRED_DOCS) {
    const p = path.join(FLOW_DOCS_DIR, name);
    if (!fs.existsSync(p)) error(`缺少 flow/docs/${name}`);
    else ok(`flow/docs/${name}`);
  }

  const cfg = path.join(TEMPLATES_DIR, 'config.yaml.tmpl');
  if (fs.existsSync(cfg)) {
    const c = fs.readFileSync(cfg, 'utf-8');
    if (!c.includes('protocol_version')) error('config.yaml.tmpl 缺少 protocol_version');
    else ok('config.yaml.tmpl protocol_version');
  }
}

function validateTemplates() {
  console.log('\n## 验证模板文件 (flow/templates/*.tmpl)\n');
  const files = fs.readdirSync(TEMPLATES_DIR).filter(f => f.endsWith('.tmpl'));

  for (const file of files) {
    const filePath = path.join(TEMPLATES_DIR, file);
    const content = fs.readFileSync(filePath, 'utf-8');
    let fileOk = true;

    const openCount = (content.match(/\{\{/g) || []).length;
    const closeCount = (content.match(/\}\}/g) || []).length;
    if (openCount !== closeCount) {
      error(`${file}: Handlebars 括号不成对（开 ${openCount} / 闭 ${closeCount}）`);
      fileOk = false;
    }

    const blockOpens = ['if', 'each', 'unless', 'with'];
    for (const tag of blockOpens) {
      const openRegex = new RegExp(`\\{{2}#${tag}\\b`, 'g');
      const closeRegex = new RegExp(`\\{{2}/${tag}\\b\\}{2}`, 'g');
      const opens = (content.match(openRegex) || []).length;
      const closes = (content.match(closeRegex) || []).length;
      if (opens !== closes) {
        error(`${file}: {{#${tag}}} 与 {{/${tag}}} 不成对（开 ${opens} / 闭 ${closes}）`);
        fileOk = false;
      }
    }

    if (fileOk) {
      ok(`${file}: Handlebars 语法检查通过`);
    }
  }
}

function validateTemplateRefs() {
  console.log('\n## 验证模板引用一致性\n');
  const templateFiles = new Set(fs.readdirSync(TEMPLATES_DIR).filter(f => f.endsWith('.tmpl')));
  const commandFiles = fs.readdirSync(COMMANDS_DIR).filter(f => f.endsWith('.md'));

  for (const file of commandFiles) {
    const filePath = path.join(COMMANDS_DIR, file);
    const content = fs.readFileSync(filePath, 'utf-8');
    const matches = [...content.matchAll(/(?:^|[`"'(\s])([^`"'\s)]+\.tmpl)/gm)]
      .map(m => path.basename(m[1]));

    for (const ref of matches) {
      if (!templateFiles.has(ref)) {
        warn(`${file}: 引用的模板 "${ref}" 在 templates/ 中不存在`);
      } else {
        ok(`${file}: 引用的模板 "${ref}" 存在`);
      }
    }
  }
}

function main() {
  console.log('========================================');
  console.log('Flow Skill 静态验证');
  console.log('========================================');

  if (!fs.existsSync(COMMANDS_DIR)) {
    console.error('错误: commands/ 目录不存在');
    process.exit(1);
  }

  validateCommands();
  validateSkillStubs();
  validateLeaseMarkers();
  validateSharedScripts();
  validateTemplates();
  validateTemplateRefs();

  console.log('\n========================================');
  console.log(`结果: ${errors} 个错误, ${warnings} 个警告`);
  console.log('========================================');

  process.exit(errors > 0 ? 1 : 0);
}

main();
