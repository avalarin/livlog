//go:build eval

package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/mark3labs/mcp-go/mcp"
)

// --- OpenRouter / OpenAI-compatible types ---

type chatMessage struct {
	Role       string     `json:"role"`
	Content    *string    `json:"content"`
	Name       string     `json:"name,omitempty"`
	ToolCalls  []toolCall `json:"tool_calls,omitempty"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
}

type toolCall struct {
	ID       string       `json:"id"`
	Type     string       `json:"type"`
	Function functionCall `json:"function"`
}

type functionCall struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"` // JSON string
}

type toolDef struct {
	Type     string       `json:"type"`
	Function toolFunction `json:"function"`
}

type toolFunction struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters"`
}

type chatRequest struct {
	Model    string        `json:"model"`
	Messages []chatMessage `json:"messages"`
	Tools    []toolDef     `json:"tools"`
}

type chatResponse struct {
	Choices []struct {
		Message chatMessage `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func strPtr(s string) *string { return &s }

func derefStr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// --- Models to evaluate ---

var evalModels = []string{
	"openai/gpt-5.2",
}

// --- Convert mcp.Tool definitions to OpenAI function-calling format ---

func mcpToolToOpenAI(t mcp.Tool) (toolDef, error) {
	schemaBytes, err := json.Marshal(t.InputSchema)
	if err != nil {
		return toolDef{}, fmt.Errorf("marshal InputSchema for %s: %w", t.Name, err)
	}

	return toolDef{
		Type: "function",
		Function: toolFunction{
			Name:        t.Name,
			Description: t.Description,
			Parameters:  json.RawMessage(schemaBytes),
		},
	}, nil
}

var openAITools = func() []toolDef {
	tools := []mcp.Tool{
		mcpToolDefs.GetCollections,
		mcpToolDefs.GetEntryTypes,
		mcpToolDefs.AddEntries,
		mcpToolDefs.FindEntries,
		mcpToolDefs.EditEntry,
	}
	result := make([]toolDef, 0, len(tools))
	for _, t := range tools {
		def, err := mcpToolToOpenAI(t)
		if err != nil {
			panic(err)
		}
		result = append(result, def)
	}
	return result
}()

// --- Eval scenarios ---

type evalStep struct {
	ExpectedTool string
	ArgChecks    map[string]string
	MockResult   string
}

type evalScenario struct {
	Name   string
	Prompt string
	System string
	Steps  []evalStep
}

var evalScenarios = []evalScenario{
	{
		Name:   "list_collections",
		Prompt: "What collections do I have?",
		Steps: []evalStep{
			{ExpectedTool: "get-collections", ArgChecks: map[string]string{}},
		},
	},
	{
		Name:   "list_entry_types",
		Prompt: "What types of entries can I create? Show me all available types.",
		Steps: []evalStep{
			{ExpectedTool: "get-entry-types", ArgChecks: map[string]string{}},
		},
	},
	{
		Name:   "add_single_movie_rated",
		Prompt: "Add the movie 'The Matrix' to my collection. I think it's great!",
		System: "The user has a collection called 'My Movies' with ID 'col-movies-0010'. Available entry types: Movie (ID: 'type-movie-uuid-0001'), Book (ID: 'type-book-uuid-0002').",
		Steps: []evalStep{
			{
				ExpectedTool: "add-entries",
				ArgChecks: map[string]string{
					"collection_id":      "col-movies-0010",
					"entries":            "len:1",
					"entries[0].title":   "contains:Matrix",
					"entries[0].score":   "3",
					"entries[0].type_id": "type-movie-uuid-0001",
				},
			},
		},
	},
	{
		Name:   "add_movie_with_score_great",
		Prompt: "I just watched Inception and it was amazing, the best movie I've seen. Add it to my movies with a great rating.",
		System: "The user has a collection 'Movies' with ID 'col-movies-001'. Entry type Movie has ID 'type-movie-001'. Score scale: 0=new, 1=bad, 2=okay, 3=great.",
		Steps: []evalStep{
			{
				ExpectedTool: "add-entries",
				ArgChecks: map[string]string{
					"collection_id":      "col-movies-001",
					"entries":            "len:1",
					"entries[0].title":   "contains:Inception",
					"entries[0].score":   "3",
					"entries[0].type_id": "type-movie-001",
				},
			},
		},
	},
	{
		Name:   "add_batch_entries",
		Prompt: "Add these three books to my reading list: '1984' by Orwell, 'Dune' by Herbert, and 'Foundation' by Asimov. I haven't read any of them yet.",
		System: "The user has a collection 'Reading List' with ID 'col-reading-001'. Entry type Book has ID 'type-book-001'. Score 0 means new/haven't read yet.",
		Steps: []evalStep{
			{
				ExpectedTool: "add-entries",
				ArgChecks: map[string]string{
					"collection_id":      "col-reading-001",
					"entries":            "len:3",
					"entries[0].title":   "contains:1984",
					"entries[1].title":   "contains:Dune",
					"entries[2].title":   "contains:Foundation",
					"entries[0].score":   "0",
					"entries[1].score":   "0",
					"entries[2].score":   "0",
					"entries[0].type_id": "type-book-001",
					"entries[1].type_id": "type-book-001",
					"entries[2].type_id": "type-book-001",
				},
			},
		},
	},
	{
		Name:   "add_movie_with_additional_fields",
		Prompt: "Add the movie 'Blade Runner 2049' to my collection, it was directed by Denis Villeneuve, released in 2017. I loved it!",
		System: "The user has a collection 'Movies' with ID 'col-movies-001'. Entry type Movie has ID 'type-movie-001', fields: [{\"key\":\"Director\",\"label\":\"Director\",\"type\":\"text\"},{\"key\":\"Year\",\"label\":\"Year\",\"type\":\"text\"}]. Score scale: 0=new, 1=bad, 2=okay, 3=great.",
		Steps: []evalStep{
			{
				ExpectedTool: "add-entries",
				ArgChecks: map[string]string{
					"collection_id":                         "col-movies-001",
					"entries":                               "len:1",
					"entries[0].title":                      "contains:Blade Runner",
					"entries[0].score":                      "3",
					"entries[0].type_id":                    "type-movie-001",
					"entries[0].additional_fields.Director": "contains:Villeneuve",
					"entries[0].additional_fields.Year":     "contains:2017",
				},
			},
		},
	},
	{
		Name:   "add_book_with_additional_fields",
		Prompt: "I just finished reading 'Neuromancer' by William Gibson, published in 1984. It was okay, not great. Add it to my books.",
		System: "The user has a collection 'Books' with ID 'col-books-001'. Entry type Book has ID 'type-book-001', fields: [{\"key\":\"Author\",\"label\":\"Author\",\"type\":\"text\"},{\"key\":\"Year\",\"label\":\"Year\",\"type\":\"text\"}]. Score scale: 0=new, 1=bad, 2=okay, 3=great.",
		Steps: []evalStep{
			{
				ExpectedTool: "add-entries",
				ArgChecks: map[string]string{
					"collection_id":                       "col-books-001",
					"entries":                             "len:1",
					"entries[0].title":                    "contains:Neuromancer",
					"entries[0].score":                    "2",
					"entries[0].type_id":                  "type-book-001",
					"entries[0].additional_fields.Author": "contains:Gibson",
					"entries[0].additional_fields.Year":   "contains:1984",
				},
			},
		},
	},
	{
		Name:   "find_by_name",
		Prompt: "Find all entries with 'Matrix' in the title.",
		Steps: []evalStep{
			{
				ExpectedTool: "find-entries",
				ArgChecks: map[string]string{
					"name": "contains:matrix",
				},
			},
		},
	},
	{
		Name:   "find_by_id",
		Prompt: "Show me the details of entry with ID 'entry-uuid-12345'.",
		Steps: []evalStep{
			{
				ExpectedTool: "find-entries",
				ArgChecks: map[string]string{
					"id": "entry-uuid-12345",
				},
			},
		},
	},
	{
		Name:   "edit_score",
		Prompt: "I rewatched that movie and it was just okay. Update entry 'entry-abc-789' to score 'okay'.",
		Steps: []evalStep{
			{
				ExpectedTool: "edit-entry",
				ArgChecks: map[string]string{
					"id":    "entry-abc-789",
					"score": "2",
				},
			},
		},
	},
	{
		Name:   "edit_title",
		Prompt: "Rename entry 'entry-rename-001' to 'The Matrix Reloaded'.",
		Steps: []evalStep{
			{
				ExpectedTool: "edit-entry",
				ArgChecks: map[string]string{
					"id":    "entry-rename-001",
					"title": "contains:Matrix Reloaded",
				},
			},
		},
	},
	{
		Name:   "edit_additional_fields",
		Prompt: "Update entry 'entry-movie-042': set the Director to 'Christopher Nolan' and Year to '2014'.",
		Steps: []evalStep{
			{
				ExpectedTool: "edit-entry",
				ArgChecks: map[string]string{
					"id":                         "entry-movie-042",
					"additional_fields.Director": "contains:Nolan",
					"additional_fields.Year":     "contains:2014",
				},
			},
		},
	},
	{
		Name:   "edit_delete_field",
		Prompt: "Remove the 'Year' field from entry 'entry-field-001'.",
		Steps: []evalStep{
			{
				ExpectedTool: "edit-entry",
				ArgChecks: map[string]string{
					"id":                       "entry-field-001",
					"additional_fields_delete": "contains:Year",
				},
			},
		},
	},
	// --- Multi-turn scenarios ---
	{
		Name:   "discover_types_then_add_entry",
		Prompt: "I want to add the movie 'Interstellar' to my Movies collection. It was amazing!",
		Steps: []evalStep{
			{
				ExpectedTool: "get-collections",
				ArgChecks:    map[string]string{},
				MockResult:   `[{"id":"col-movies-001","name":"Movies","icon":"system:movie","entry_count":5}]`,
			},
			{
				ExpectedTool: "get-entry-types",
				ArgChecks:    map[string]string{},
				MockResult:   `[{"id":"type-movie-001","name":"Movie","icon":"system:movie","fields":[{"key":"Year","label":"Year","type":"text"}]}]`,
			},
			{
				ExpectedTool: "add-entries",
				ArgChecks: map[string]string{
					"collection_id":      "col-movies-001",
					"entries":            "len:1",
					"entries[0].title":   "contains:Interstellar",
					"entries[0].score":   "3",
					"entries[0].type_id": "type-movie-001",
				},
				MockResult: `{"created_ids":["new-entry-001"]}`,
			},
		},
	},
	{
		Name:   "find_then_edit",
		Prompt: "Find the movie 'Inception' and change its rating to great.",
		Steps: []evalStep{
			{
				ExpectedTool: "find-entries",
				ArgChecks: map[string]string{
					"name": "contains:inception",
				},
				MockResult: `[{"id":"entry-inception-001","title":"Inception","score":1,"description":"Inception","date":"2024-01-01","additional_fields":{}}]`,
			},
			{
				ExpectedTool: "edit-entry",
				ArgChecks: map[string]string{
					"id":    "entry-inception-001",
					"score": "3",
				},
				MockResult: `{"id":"entry-inception-001","title":"Inception","score":3,"description":"Inception","date":"2024-01-01","additional_fields":{}}`,
			},
		},
	},
	{
		Name:   "list_collections_then_find_entries",
		Prompt: "Show me the entries in my Movies collection.",
		Steps: []evalStep{
			{
				ExpectedTool: "get-collections",
				ArgChecks:    map[string]string{},
				MockResult:   `[{"id":"col-movies-001","name":"Movies","icon":"system:movie","entry_count":5}]`,
			},
			{
				ExpectedTool: "find-entries",
				ArgChecks: map[string]string{
					"collection_id": "col-movies-001",
				},
				MockResult: `[{"id":"e1","title":"Inception","score":3},{"id":"e2","title":"The Matrix","score":3}]`,
			},
		},
	},
	{
		Name:   "discover_types_then_add_with_fields",
		Prompt: "Add the game 'The Witcher 3' to my games collection. It came out in 2015 by CD Projekt Red. Best game ever!",
		Steps: []evalStep{
			{
				ExpectedTool: "get-collections",
				ArgChecks:    map[string]string{},
				MockResult:   `[{"id":"col-games-001","name":"Games","icon":"system:game","entry_count":3}]`,
			},
			{
				ExpectedTool: "get-entry-types",
				ArgChecks:    map[string]string{},
				MockResult:   `[{"id":"type-game-001","name":"Game","icon":"system:game","fields":[{"key":"Developer","label":"Developer","type":"text"},{"key":"Year","label":"Year","type":"text"}]}]`,
			},
			{
				ExpectedTool: "add-entries",
				ArgChecks: map[string]string{
					"collection_id":                          "col-games-001",
					"entries":                                "len:1",
					"entries[0].title":                       "contains:Witcher",
					"entries[0].score":                       "3",
					"entries[0].type_id":                     "type-game-001",
					"entries[0].additional_fields.Developer": "contains:CD Projekt",
					"entries[0].additional_fields.Year":      "contains:2015",
				},
				MockResult: `{"created_ids":["new-entry-002"]}`,
			},
		},
	},
	{
		Name:   "find_then_edit_fields",
		Prompt: "Find the movie 'Dune' and update its Director to 'Denis Villeneuve' and Year to '2021'.",
		Steps: []evalStep{
			{
				ExpectedTool: "find-entries",
				ArgChecks: map[string]string{
					"name": "contains:dune",
				},
				MockResult: `[{"id":"entry-dune-001","title":"Dune","score":3,"description":"Dune","date":"2024-01-01","additional_fields":{"Year":"2020"}}]`,
			},
			{
				ExpectedTool: "edit-entry",
				ArgChecks: map[string]string{
					"id":                         "entry-dune-001",
					"additional_fields.Director": "contains:Villeneuve",
					"additional_fields.Year":     "contains:2021",
				},
				MockResult: `{"id":"entry-dune-001","title":"Dune","score":3,"description":"Dune","date":"2024-01-01","additional_fields":{"Director":"Denis Villeneuve","Year":"2021"}}`,
			},
		},
	},
}

// --- OpenRouter API call ---

func callOpenRouter(ctx context.Context, apiKey, model string, messages []chatMessage) (*chatResponse, error) {
	reqBody := chatRequest{
		Model:    model,
		Messages: messages,
		Tools:    openAITools,
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://openrouter.ai/api/v1/chat/completions", bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("HTTP-Referer", "https://livlog.app")
	req.Header.Set("X-Title", "livlog MCP Eval")

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("HTTP request: %w", err)
	}
	defer resp.Body.Close() //nolint:errcheck

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned HTTP %d: %s", resp.StatusCode, string(respBody))
	}

	var chatResp chatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w", err)
	}

	if chatResp.Error != nil {
		return nil, fmt.Errorf("API error: %s", chatResp.Error.Message)
	}

	return &chatResp, nil
}

// --- Argument checking ---

type checkResult struct {
	Key      string
	Expected string
	Actual   string
	Passed   bool
}

// resolveArg navigates into args using a dotted key path.
// Supports array indexing: "entries[0].title" -> args["entries"][0]["title"].
func resolveArg(args map[string]interface{}, key string) (interface{}, bool) {
	var current interface{} = args
	for _, seg := range strings.Split(key, ".") {
		if idx := strings.Index(seg, "["); idx != -1 {
			name := seg[:idx]
			indexStr := strings.TrimSuffix(seg[idx+1:], "]")

			m, ok := current.(map[string]interface{})
			if !ok {
				return nil, false
			}
			arr, ok := m[name].([]interface{})
			if !ok {
				return nil, false
			}
			var i int
			if _, err := fmt.Sscanf(indexStr, "%d", &i); err != nil || i < 0 || i >= len(arr) {
				return nil, false
			}
			current = arr[i]
		} else {
			m, ok := current.(map[string]interface{})
			if !ok {
				return nil, false
			}
			val, exists := m[seg]
			if !exists {
				return nil, false
			}
			current = val
		}
	}
	return current, true
}

func checkArgs(args map[string]interface{}, checks map[string]string) []checkResult {
	var results []checkResult

	for key, expected := range checks {
		actual, exists := resolveArg(args, key)

		if !exists {
			results = append(results, checkResult{
				Key: key, Expected: expected, Actual: "<missing>", Passed: false,
			})
			continue
		}

		switch {
		case expected == "*":
			results = append(results, checkResult{
				Key: key, Expected: "(exists)", Actual: fmt.Sprintf("%v", actual), Passed: true,
			})

		case strings.HasPrefix(expected, "len:"):
			var expectedLen int
			if n, err := fmt.Sscanf(expected, "len:%d", &expectedLen); err != nil || n != 1 {
				results = append(results, checkResult{
					Key: key, Expected: expected, Actual: "bad len: pattern", Passed: false,
				})
				continue
			}
			arr, ok := actual.([]interface{})
			if !ok {
				results = append(results, checkResult{
					Key: key, Expected: expected, Actual: fmt.Sprintf("not an array: %T", actual), Passed: false,
				})
				continue
			}
			passed := len(arr) == expectedLen
			results = append(results, checkResult{
				Key: key, Expected: expected, Actual: fmt.Sprintf("len:%d", len(arr)), Passed: passed,
			})

		case strings.HasPrefix(expected, "contains:"):
			needle := strings.TrimPrefix(expected, "contains:")
			haystack := fmt.Sprintf("%v", actual)
			passed := strings.Contains(strings.ToLower(haystack), strings.ToLower(needle))
			results = append(results, checkResult{
				Key: key, Expected: expected, Actual: haystack, Passed: passed,
			})

		default:
			actualStr := fmt.Sprintf("%v", actual)
			passed := actualStr == expected
			results = append(results, checkResult{
				Key: key, Expected: expected, Actual: actualStr, Passed: passed,
			})
		}
	}

	// Sort results by key for stable output.
	sort.Slice(results, func(i, j int) bool {
		return results[i].Key < results[j].Key
	})

	return results
}

// --- Report printing ---

// printSystemPrompt prints the tool descriptions and system context that the
// agent receives, so the reader understands what the model is working with.
func printSystemPrompt() {
	fmt.Println("================================================================================")
	fmt.Println("  SYSTEM PROMPT & TOOL DESCRIPTIONS SENT TO THE AGENT")
	fmt.Println("================================================================================")
	fmt.Println()
	fmt.Printf("  Tools provided: %d\n", len(openAITools))
	fmt.Println()
	for i, td := range openAITools {
		desc := td.Function.Description
		if len(desc) > 120 {
			desc = desc[:120] + "..."
		}
		// Pretty-print the parameters schema.
		var params interface{}
		_ = json.Unmarshal(td.Function.Parameters, &params)
		paramsJSON, _ := json.MarshalIndent(params, "      ", "  ")

		fmt.Printf("  [%d] %s\n", i+1, td.Function.Name)
		fmt.Printf("      %s\n", desc)
		fmt.Printf("      parameters:\n      %s\n\n", string(paramsJSON))
	}
	fmt.Println("================================================================================")
	fmt.Println()
}

// printStepResult prints a human-readable block for one step of a scenario.
func printStepResult(
	scenario evalScenario,
	stepIdx int,
	step evalStep,
	passed bool,
	tc *toolCall,
	rawArgs string,
	argResults []checkResult,
	reasoning string,
) {
	totalSteps := len(scenario.Steps)
	status := "\033[32mPASS\033[0m"
	if !passed {
		status = "\033[31mFAIL\033[0m"
	}

	fmt.Printf("  [%s] %s  step %d/%d\n", status, scenario.Name, stepIdx+1, totalSteps)

	// Show the user prompt on the first step.
	if stepIdx == 0 {
		prompt := scenario.Prompt
		if scenario.System != "" {
			prompt += "  [context: " + truncate(scenario.System, 80) + "]"
		}
		fmt.Printf("         prompt:   %s\n", truncate(prompt, 120))
	}

	// Show reasoning if the model produced text alongside tool calls.
	if reasoning != "" {
		fmt.Printf("         thinking: %s\n", truncate(reasoning, 200))
	}

	if tc == nil {
		fmt.Printf("         tool:     <none> (no tool call)\n")
		fmt.Println()
		return
	}

	// Tool call line.
	toolStatus := "\033[32m✓\033[0m"
	if tc.Function.Name != step.ExpectedTool {
		toolStatus = "\033[31m✗\033[0m"
	}
	if tc.Function.Name == step.ExpectedTool {
		fmt.Printf("         tool:     %s %s\n", toolStatus, tc.Function.Name)
	} else {
		fmt.Printf("         tool:     %s %s  (expected: %s)\n", toolStatus, tc.Function.Name, step.ExpectedTool)
	}

	// Arguments — show full JSON for failed steps.
	if !passed {
		// Pretty-print the raw arguments.
		var pretty interface{}
		if err := json.Unmarshal([]byte(rawArgs), &pretty); err == nil {
			prettyJSON, _ := json.MarshalIndent(pretty, "                   ", "  ")
			fmt.Printf("         args:     %s\n", string(prettyJSON))
		} else {
			fmt.Printf("         args:     %s\n", rawArgs)
		}
	}

	// Per-field checks.
	if len(argResults) > 0 {
		hasFailures := false
		for _, r := range argResults {
			if !r.Passed {
				hasFailures = true
				break
			}
		}

		if hasFailures {
			fmt.Println("         checks:")
			for _, r := range argResults {
				if r.Passed {
					fmt.Printf("           \033[32m✓\033[0m %-40s  = %s\n", r.Key, r.Actual)
				} else {
					fmt.Printf("           \033[31m✗\033[0m %-40s  expected: %-20s  got: %s\n", r.Key, r.Expected, r.Actual)
				}
			}
		} else {
			// All passed — compact summary.
			keys := make([]string, 0, len(argResults))
			for _, r := range argResults {
				keys = append(keys, r.Key)
			}
			fmt.Printf("         checks:   all %d passed (%s)\n", len(argResults), strings.Join(keys, ", "))
		}
	}

	fmt.Println()
}

// --- Main eval test ---

func TestMCP_Eval(t *testing.T) {
	apiKey := os.Getenv("OPENROUTER_API_KEY")
	if apiKey == "" {
		t.Skip("OPENROUTER_API_KEY not set — skipping MCP eval")
	}

	// Print the tool descriptions once so the reader sees what the agent gets.
	printSystemPrompt()

	for _, model := range evalModels {
		model := model
		t.Run(model, func(t *testing.T) {
			var passed, total int

			fmt.Printf("================================================================================\n")
			fmt.Printf("  MODEL: %s\n", model)
			fmt.Printf("================================================================================\n\n")

			for _, scenario := range evalScenarios {
				total++
				result := runScenario(t, apiKey, model, scenario)
				if result {
					passed++
				}
			}

			pct := float64(passed) / float64(total) * 100
			fmt.Println("--------------------------------------------------------------------------------")
			fmt.Printf("  RESULT: %s  %d/%d scenarios passed (%.1f%%)\n", model, passed, total, pct)
			fmt.Println("--------------------------------------------------------------------------------")
			fmt.Println()
		})
	}
}

func runScenario(t *testing.T, apiKey, model string, scenario evalScenario) bool {
	t.Helper()

	messages := []chatMessage{}
	if scenario.System != "" {
		messages = append(messages, chatMessage{Role: "system", Content: strPtr(scenario.System)})
	}
	messages = append(messages, chatMessage{Role: "user", Content: strPtr(scenario.Prompt)})

	allOK := true

	for stepIdx, step := range scenario.Steps {
		resp, err := callOpenRouter(t.Context(), apiKey, model, messages)
		if err != nil {
			fmt.Printf("  [\033[31mERR\033[0m]  %s  step %d/%d\n", scenario.Name, stepIdx+1, len(scenario.Steps))
			fmt.Printf("         %v\n\n", err)
			return false
		}

		if len(resp.Choices) == 0 {
			fmt.Printf("  [\033[31mERR\033[0m]  %s  step %d/%d\n", scenario.Name, stepIdx+1, len(scenario.Steps))
			fmt.Printf("         No choices in API response\n\n")
			return false
		}

		msg := resp.Choices[0].Message

		// Extract reasoning — the model may produce text alongside tool calls.
		reasoning := derefStr(msg.Content)

		if len(msg.ToolCalls) == 0 {
			printStepResult(scenario, stepIdx, step, false, nil, "", nil, reasoning)
			return false
		}

		tc := msg.ToolCalls[0]
		toolOK := tc.Function.Name == step.ExpectedTool

		var args map[string]interface{}
		if err := json.Unmarshal([]byte(tc.Function.Arguments), &args); err != nil {
			fmt.Printf("  [\033[31mERR\033[0m]  %s  step %d/%d\n", scenario.Name, stepIdx+1, len(scenario.Steps))
			fmt.Printf("         Failed to parse arguments: %v\n", err)
			fmt.Printf("         raw: %s\n\n", tc.Function.Arguments)
			return false
		}

		argResults := checkArgs(args, step.ArgChecks)
		stepArgsOK := true
		for _, r := range argResults {
			if !r.Passed {
				stepArgsOK = false
			}
		}

		stepOK := toolOK && stepArgsOK
		if !stepOK {
			allOK = false
		}

		printStepResult(scenario, stepIdx, step, stepOK, &tc, tc.Function.Arguments, argResults, reasoning)

		if !stepOK {
			return false
		}

		// Feed mock result back for multi-turn.
		if stepIdx < len(scenario.Steps)-1 {
			mockResult := step.MockResult
			if mockResult == "" {
				mockResult = `{"ok":true}`
			}
			messages = append(messages, chatMessage{
				Role:      "assistant",
				ToolCalls: msg.ToolCalls,
			})
			for i, call := range msg.ToolCalls {
				content := `{"ok":true}`
				if i == 0 {
					content = mockResult
				}
				messages = append(messages, chatMessage{
					Role:       "tool",
					ToolCallID: call.ID,
					Name:       call.Function.Name,
					Content:    strPtr(content),
				})
			}
		}
	}

	return allOK
}

func truncate(s string, maxLen int) string {
	s = strings.ReplaceAll(s, "\n", " ")
	if len(s) > maxLen {
		return s[:maxLen] + "..."
	}
	return s
}
