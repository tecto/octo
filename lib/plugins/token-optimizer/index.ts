/**
 * OCTO Token Optimizer Plugin for OpenClaw
 *
 * This plugin integrates with OpenClaw to provide:
 * - Prompt caching configuration
 * - Model tiering recommendations
 * - Cost tracking
 * - Session monitoring
 */

import { spawn } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

// Configuration
const OCTO_HOME = process.env.OCTO_HOME || path.join(process.env.HOME || '', '.octo');
const LIB_DIR = path.dirname(path.dirname(__dirname));

interface PluginConfig {
  promptCaching: {
    enabled: boolean;
    cacheSystemPrompt: boolean;
    cacheTools: boolean;
    cacheHistoryOlderThan: number;
  };
  modelTiering: {
    enabled: boolean;
    defaultModel: string;
  };
  costTracking: {
    enabled: boolean;
  };
}

interface RequestContext {
  sessionId?: string;
  model?: string;
  messages?: any[];
}

interface ResponseUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
}

// Load configuration
function loadConfig(): PluginConfig {
  const configPath = path.join(OCTO_HOME, 'config.json');

  if (fs.existsSync(configPath)) {
    try {
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
      return {
        promptCaching: config.optimization?.promptCaching || { enabled: true },
        modelTiering: config.optimization?.modelTiering || { enabled: true, defaultModel: 'sonnet' },
        costTracking: config.costTracking || { enabled: true },
      };
    } catch (e) {
      console.error('Failed to load OCTO config:', e);
    }
  }

  // Default config
  return {
    promptCaching: {
      enabled: true,
      cacheSystemPrompt: true,
      cacheTools: true,
      cacheHistoryOlderThan: 5,
    },
    modelTiering: {
      enabled: true,
      defaultModel: 'sonnet',
    },
    costTracking: {
      enabled: true,
    },
  };
}

// Model tiering patterns
const HAIKU_PATTERNS = [
  /^(what|which|where|when|who|how many)\b/i,
  /\b(list|show|display|get)\s+(files?|dirs?|folders?)/i,
  /^(yes|no|confirm|cancel|ok|done)\b/i,
  /\buse\s+(the\s+)?(grep|glob|read|bash)\s+tool/i,
];

const OPUS_PATTERNS = [
  /\b(architect|design|plan)\b.*\b(system|service|infrastructure)/i,
  /\b(trade-?off|compare|evaluate)\b.*\b(approach|solution|option)/i,
  /\b(security|vulnerability|attack)\b.*\b(audit|review|assess)/i,
];

function classifyMessage(message: string): string {
  // Check Haiku patterns first (cheapest)
  for (const pattern of HAIKU_PATTERNS) {
    if (pattern.test(message)) {
      return 'haiku';
    }
  }

  // Check Opus patterns
  for (const pattern of OPUS_PATTERNS) {
    if (pattern.test(message)) {
      return 'opus';
    }
  }

  // Default to Sonnet
  return 'sonnet';
}

// Cost tracking
function recordCost(
  model: string,
  usage: ResponseUsage,
  sessionId?: string
): void {
  const costsDir = path.join(OCTO_HOME, 'costs');

  if (!fs.existsSync(costsDir)) {
    fs.mkdirSync(costsDir, { recursive: true });
  }

  const today = new Date().toISOString().split('T')[0];
  const costFile = path.join(costsDir, `${today}.jsonl`);

  // Simple pricing (can be loaded from config)
  const pricing: Record<string, Record<string, number>> = {
    'opus': { input: 15.0, output: 75.0, cache_read: 1.5, cache_write: 18.75 },
    'sonnet': { input: 3.0, output: 15.0, cache_read: 0.3, cache_write: 3.75 },
    'haiku': { input: 0.8, output: 4.0, cache_read: 0.08, cache_write: 1.0 },
  };

  // Determine model tier
  let tier = 'sonnet';
  if (model.includes('opus')) tier = 'opus';
  else if (model.includes('haiku')) tier = 'haiku';

  const p = pricing[tier];

  const inputTokens = usage.input_tokens || 0;
  const outputTokens = usage.output_tokens || 0;
  const cacheRead = usage.cache_read_input_tokens || 0;
  const cacheWrite = usage.cache_creation_input_tokens || 0;

  const actualInput = Math.max(0, inputTokens - cacheRead);

  const record = {
    timestamp: new Date().toISOString(),
    model,
    input_tokens: inputTokens,
    output_tokens: outputTokens,
    cache_read_tokens: cacheRead,
    cache_write_tokens: cacheWrite,
    input_cost: (actualInput / 1_000_000) * p.input,
    output_cost: (outputTokens / 1_000_000) * p.output,
    cache_read_cost: (cacheRead / 1_000_000) * p.cache_read,
    cache_write_cost: (cacheWrite / 1_000_000) * p.cache_write,
    total: 0,
    session_id: sessionId,
  };

  record.total =
    record.input_cost +
    record.output_cost +
    record.cache_read_cost +
    record.cache_write_cost;

  fs.appendFileSync(costFile, JSON.stringify(record) + '\n');
}

// Plugin exports
export const name = 'token-optimizer';
export const version = '1.0.0';

let config: PluginConfig;

export function initialize(): void {
  config = loadConfig();
  console.log('[OCTO] Token optimizer plugin initialized');
}

export function onBeforeRequest(
  request: any,
  context: RequestContext
): any {
  if (!config) {
    config = loadConfig();
  }

  // Apply model tiering
  if (config.modelTiering.enabled && request.messages?.length > 0) {
    const lastUserMessage = [...request.messages]
      .reverse()
      .find((m: any) => m.role === 'user');

    if (lastUserMessage) {
      const content =
        typeof lastUserMessage.content === 'string'
          ? lastUserMessage.content
          : JSON.stringify(lastUserMessage.content);

      const recommended = classifyMessage(content);

      // Only tier down, never up from what's requested
      const currentTier = request.model?.includes('opus')
        ? 'opus'
        : request.model?.includes('haiku')
        ? 'haiku'
        : 'sonnet';

      if (
        recommended === 'haiku' &&
        currentTier !== 'haiku' &&
        !request.model?.includes('opus')
      ) {
        request.model = 'claude-haiku-3-5-20241022';
      }
    }
  }

  // Apply prompt caching headers
  if (config.promptCaching.enabled) {
    request.headers = {
      ...request.headers,
      'anthropic-beta': 'prompt-caching-2024-07-31',
    };

    // Add cache control to system messages and tools
    if (request.system && config.promptCaching.cacheSystemPrompt) {
      if (typeof request.system === 'string') {
        request.system = [
          {
            type: 'text',
            text: request.system,
            cache_control: { type: 'ephemeral' },
          },
        ];
      }
    }
  }

  return request;
}

export function onAfterResponse(
  request: any,
  response: any,
  context: RequestContext
): void {
  if (!config) {
    config = loadConfig();
  }

  // Track costs
  if (config.costTracking.enabled && response.usage) {
    recordCost(response.model || request.model, response.usage, context.sessionId);
  }
}

// CLI for testing
if (require.main === module) {
  initialize();

  const testMessage = process.argv.slice(2).join(' ') || 'Write a function to parse JSON';
  const tier = classifyMessage(testMessage);

  console.log(`Message: "${testMessage}"`);
  console.log(`Recommended tier: ${tier}`);
}
