#!/usr/bin/env node
/**
 * Flow Skill 静态验证脚本
 * 检查命令文件 frontmatter、模板语法、文件一致性。
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const COMMANDS_DIR = path.join(ROOT, 'flow', 'commands');
const TEMPLATES_DIR = path.join(ROOT, 'flow', 'templates');

const REQUIRED_FRONTMATTER = ['name', 'description', 'category', 'tags', 'version'];
const COMMAND_TO_NAME_MAP = {
  'init.md': 'Init',
  'assign.md': 'Assign',
  'receive.md': 'Receive',
  'report.md': 'Report',
  'status.md': 'Status',
  'verify.md': 'Verify',
  'archive.md': 'Archive',
};

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

// 解析 Markdown 文件的 YAML frontmatter
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
    // 去除引号
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

// 检查命令文件
function validateCommands() {
  console.log('\n## 验证命令文件 (flow/commands/*.md)\n');
  const files = fs.readdirSync(COMMANDS_DIR).filter(f => f.endsWith('.md'));

  for (const file of files) {
    const filePath = path.join(COMMANDS_DIR, file);
    const result = parseFrontmatter(filePath);

    if (!result) {
      error(`${file}: 缺少 YAML frontmatter`);
      continue;
    }

    const { data } = result;
    let fileOk = true;

    for (const key of REQUIRED_FRONTMATTER) {
      if (!(key in data) || data[key] === '' || data[key] == null) {
        error(`${file}: frontmatter 缺少必填字段 "${key}"`);
        fileOk = false;
      }
    }

    // 检查 name 与文件名的对应关系
    const expectedKeyword = COMMAND_TO_NAME_MAP[file];
    if (expectedKeyword && data.name) {
      if (!data.name.includes(expectedKeyword)) {
        warn(`${file}: frontmatter name "${data.name}" 未包含预期的关键词 "${expectedKeyword}"`);
        fileOk = false;
      }
    }

    // 检查 tags 是否为数组
    if (data.tags && !Array.isArray(data.tags)) {
      warn(`${file}: tags 应为数组格式`);
      fileOk = false;
    }

    if (fileOk) {
      ok(`${file}: frontmatter 完整`);
    }
  }
}

// 检查模板文件 Handlebars 语法
function validateTemplates() {
  console.log('\n## 验证模板文件 (flow/templates/*.tmpl)\n');
  const files = fs.readdirSync(TEMPLATES_DIR).filter(f => f.endsWith('.tmpl'));

  for (const file of files) {
    const filePath = path.join(TEMPLATES_DIR, file);
    const content = fs.readFileSync(filePath, 'utf-8');
    let fileOk = true;

    // 基本括号配对检查
    const openCount = (content.match(/\{\{/g) || []).length;
    const closeCount = (content.match(/\}\}/g) || []).length;
    if (openCount !== closeCount) {
      error(`${file}: Handlebars 括号不成对（开 ${openCount} / 闭 ${closeCount}）`);
      fileOk = false;
    }

    // 检查未闭合的块级标签
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

// 检查命令文件引用的模板是否存在
function validateTemplateRefs() {
  console.log('\n## 验证模板引用一致性\n');
  const templateFiles = new Set(fs.readdirSync(TEMPLATES_DIR).filter(f => f.endsWith('.tmpl')));
  const commandFiles = fs.readdirSync(COMMANDS_DIR).filter(f => f.endsWith('.md'));

  for (const file of commandFiles) {
    const filePath = path.join(COMMANDS_DIR, file);
    const content = fs.readFileSync(filePath, 'utf-8');

    // 匹配引用的模板文件（如 assign.md.tmpl、child-config.yaml.tmpl 等）
    const refs = content.match(/[\w-]+\.(tmpl|tmpl\))+/g) || [];
    // 更精确的匹配：*.tmpl 或 .tmpl 结尾的词
    const matches = [...content.matchAll(/(\w[\w.-]*\.tmpl)/g)].map(m => m[1]);

    for (const ref of matches) {
      if (!templateFiles.has(ref)) {
        warn(`${file}: 引用的模板 "${ref}" 在 templates/ 中不存在`);
      } else {
        ok(`${file}: 引用的模板 "${ref}" 存在`);
      }
    }
  }
}

// 主入口
function main() {
  console.log('========================================');
  console.log('Flow Skill 静态验证');
  console.log('========================================');

  if (!fs.existsSync(COMMANDS_DIR)) {
    console.error('错误: commands/ 目录不存在');
    process.exit(1);
  }

  validateCommands();
  validateTemplates();
  validateTemplateRefs();

  console.log('\n========================================');
  console.log(`结果: ${errors} 个错误, ${warnings} 个警告`);
  console.log('========================================');

  process.exit(errors > 0 ? 1 : 0);
}

main();
