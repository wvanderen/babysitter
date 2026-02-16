package keymap

type Command struct {
	ID       string
	Name     string
	Key      string
	Context  string
	Priority int
}

type Registry struct {
	commands []Command
}

func NewRegistry() *Registry {
	return &Registry{
		commands: []Command{},
	}
}

func (r *Registry) Register(cmd Command) {
	r.commands = append(r.commands, cmd)
}

func (r *Registry) CommandsForContext(context string) []Command {
	var result []Command
	for _, cmd := range r.commands {
		if cmd.Context == context || cmd.Context == "" {
			result = append(result, cmd)
		}
	}
	return result
}

func (r *Registry) AllCommands() []Command {
	return r.commands
}

func RenderHints(cmds []Command, maxWidth int) string {
	if len(cmds) == 0 {
		return ""
	}

	var hints []string
	currentWidth := 0

	for _, cmd := range cmds {
		hint := "[" + cmd.Key + "] " + cmd.Name
		hintWidth := len(hint) + 2

		if currentWidth+hintWidth > maxWidth && len(hints) > 0 {
			break
		}

		hints = append(hints, hint)
		currentWidth += hintWidth
	}

	if len(hints) == 0 {
		return ""
	}

	result := ""
	for i, hint := range hints {
		if i > 0 {
			result += "  "
		}
		result += hint
	}

	return result
}

var DefaultRegistry = NewRegistry()

func Register(cmd Command) {
	DefaultRegistry.Register(cmd)
}

func CommandsForContext(context string) []Command {
	return DefaultRegistry.CommandsForContext(context)
}

func init() {
	DefaultRegistry.Register(Command{ID: "navigate-up", Name: "Up", Key: "↑", Context: "sidebar", Priority: 1})
	DefaultRegistry.Register(Command{ID: "navigate-down", Name: "Down", Key: "↓", Context: "sidebar", Priority: 1})
	DefaultRegistry.Register(Command{ID: "new-session", Name: "New", Key: "n", Context: "sidebar", Priority: 2})
	DefaultRegistry.Register(Command{ID: "attach", Name: "Attach", Key: "a", Context: "sidebar", Priority: 3})
	DefaultRegistry.Register(Command{ID: "pause", Name: "Pause", Key: "p", Context: "sidebar", Priority: 4})
	DefaultRegistry.Register(Command{ID: "resume", Name: "Resume", Key: "r", Context: "sidebar", Priority: 4})
	DefaultRegistry.Register(Command{ID: "refresh", Name: "Refresh", Key: "R", Context: "sidebar", Priority: 5})
	DefaultRegistry.Register(Command{ID: "quit", Name: "Quit", Key: "q", Context: "", Priority: 10})

	DefaultRegistry.Register(Command{ID: "focus-sidebar", Name: "Sidebar", Key: "Tab", Context: "main", Priority: 1})
}
