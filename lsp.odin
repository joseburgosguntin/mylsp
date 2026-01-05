package mylsp

Message :: struct {
	jsonrpc: string,
}

Request :: struct {
	using _: Message,
	id:      int,
	method:  string,
}

Response :: struct {
	using _: Message,
	id:      Maybe(int),
}

Notification :: struct {
	using _: Message,
	method:  string,
}

InitializeRequest :: struct {
	using _: Request,
	params:  struct {
		clientInfo: struct {
			name:    string,
			version: string,
		},
	},
}

InitializeResponse :: struct {
	using _: Response,
	result:  struct {
		capabilities: struct {
			textDocumentSync:   Maybe(enum {
					None        = 0,
					Full        = 1,
					Incremental = 2,
				}),
			hoverProvider:      bool,
			definitionProvider: bool,
			codeActionProvider: bool,
			completionProvider: map[string]any,
			// TODO
		},
		serverInfo:   struct {
			name:    string,
			version: string,
		},
	},
}

TextDocumentItem :: struct {
	uri:        string,
	languageId: string,
	version:    int,
	text:       string,
}

TextDocumentIdentifier :: struct {
	uri: string,
}

VersionedTextDocumentIdentifier :: struct {
	using _: TextDocumentIdentifier,
	version: int,
}

DidOpenTextDocumentNotification :: struct {
	using _: Notification,
	params:  struct {
		textDocument: TextDocumentItem,
	},
}

DidChangeTextDocumentNotification :: struct {
	using _: Notification,
	params:  struct {
		textDocument:   VersionedTextDocumentIdentifier,
		contentChanges: []struct {
			text: string,
		},
	},
}

Position :: struct {
	line, character: uint,
}

TextDocumentPositionParams :: struct {
	textDocument: TextDocumentIdentifier,
	position:     Position,
}

HoverRequest :: struct {
	using _: Request,
	params:  struct {
		using _: TextDocumentPositionParams,
	},
}

HoverResponse :: struct {
	using _: Response,
	result:  struct {
		contents: string,
	},
}

DefinitionRequest :: struct {
	using _: Request,
	params:  struct {
		using _: TextDocumentPositionParams,
	},
}

DefinitionResponse :: struct {
	using _: Response,
	result:  Location,
}

Location :: struct {
	uri:   string,
	range: Range,
}

Range :: struct {
	start, end: Position,
}


CodeActionRequest :: struct {
	using _: Request,
	params:  struct {
		textDocument: TextDocumentIdentifier,
		range:        Range,
		context_:     CodeActionContext `json:"context"`,
	},
}

CodeAction :: struct {
	title: string,
	edit:  WorkspaceEdit,
}

WorkspaceEdit :: struct {
	changes: map[string][]TextEdit,
}

TextEdit :: struct {
	range:   Range,
	newText: string,
}

CodeActionResponse :: struct {
	using _: Response,
	result:  []CodeAction,
}

CodeActionContext :: struct {
	// TODO
}

CompletionRequest :: struct {
	using _: Request,
	params:  struct {
		using _: TextDocumentPositionParams,
	},
}

CompletionItem :: struct {
	label:         string,
	// TODO: kind for if its a function or smth
	detail:        string,
	documentation: string,
	// TODO: insertText does the auto import stuff
}

CompletionResponse :: struct {
	using _: Response,
	result:  []CompletionItem,
}

PublishDiagnosticsNotification :: struct {
	using _: Notification,
	params:  struct {
		uri:         string,
		diagnostics: []Diagnostic,
	},
	// TODO: continue filling this up
}

Diagnostic :: struct {
	range:    Range,
	severity: enum {
		Error       = 1,
		Warning     = 2,
		Information = 3,
		Hint        = 4,
	},
	source:   string,
	message:  string,
}
