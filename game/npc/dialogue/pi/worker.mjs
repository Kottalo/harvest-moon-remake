import { createInterface } from "node:readline";
import { Agent } from "@earendil-works/pi-agent-core";
import { streamSimple } from "@earendil-works/pi-ai/api/openai-completions";

const model = {
  id: "deepseek-flash",
  name: "DeepSeek Flash",
  provider: "deepseek",
  api: "openai-completions",
  baseUrl: "https://api.deepseek.com",
  reasoning: true,
  input: ["text"],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  contextWindow: 1_000_000,
  maxTokens: 160,
};

const write = (event) => process.stdout.write(JSON.stringify(event) + "\n");
const textOf = (message) => message.content
  .filter((part) => part.type === "text").map((part) => part.text).join("");

async function respond({ key, messages }) {
  // World history supplies each actor's witnessed memories. Pi holds only this
  // response, so private messages never carry into another actor's context.
  const agent = new Agent({
    initialState: { model, systemPrompt: messages[0].content, tools: [], thinkingLevel: "off" },
    getApiKey: () => key,
    identity: { attribution: null },
    streamFn: (target, context, options) => streamSimple(target, context, {
      ...options, maxTokens: 160, maxRetries: 0,
      onPayload: (payload) => ({ ...payload, thinking: { type: "disabled" } }),
    }),
  });
  agent.subscribe((event) => {
    if (event.type === "message_update" && event.assistantMessageEvent.type === "text_delta") {
      write({ partial: textOf(event.message).slice(0, 180) });
    }
  });
  await agent.prompt(messages[1].content);
  const answer = agent.state.messages.at(-1);
  if (answer?.role !== "assistant" || answer.stopReason === "error" || answer.stopReason === "aborted") {
    const status = answer?.errorMessage?.match(/\b(401|402|429)\b/)?.[1];
    const problem = {
      401: "DeepSeek 密钥无效或已撤销。",
      402: "DeepSeek 账户余额不足。",
      429: "请求太频繁，请稍后再试。",
    }[status] ?? "Pi Agent 未能取得 DeepSeek 回复。";
    write({ problem });
    return;
  }
  const { input, output, cacheRead, cacheWrite } = answer.usage;
  write({ answer: textOf(answer).trim().slice(0, 180), usage: { input, output, cacheRead, cacheWrite } });
}

let request = "";
for await (const line of createInterface({ input: process.stdin, crlfDelay: Infinity })) {
  request += line.slice(1);
  if (line.startsWith("+")) {
    write({ ack: true });
    continue;
  }
  try {
    await respond(JSON.parse(Buffer.from(request, "base64").toString("utf8")));
  } catch {
    write({ problem: "Pi Agent 对话中断，请重试。" });
  } finally {
    request = "";
  }
}
