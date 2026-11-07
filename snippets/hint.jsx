export const Hint = ({ kind, children }) => {
  const [open, setOpen] = useState(false);
  const colors = {
    red: { badge: "#dc2626", border: "#fca5a5", background: "#fef2f2", text: "#7f1d1d" },
    yellow: { badge: "#ca8a04", border: "#fde68a", background: "#fffbeb", text: "#713f12" },
    grey: { badge: "#6b7280", border: "#d1d5db", background: "#f9fafb", text: "#1f2937" },
  };
  const color = colors[kind] || colors.grey;

  return (
    <span
      style={{ position: "relative", display: "inline-block", marginLeft: "0.25rem", verticalAlign: "middle" }}
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
    >
      <button
        type="button"
        aria-label="Meer informatie"
        aria-expanded={open}
        onClick={() => setOpen(!open)}
        onFocus={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        style={{
          width: "1.1rem",
          height: "1.1rem",
          borderRadius: "9999px",
          border: "none",
          background: color.badge,
          color: "#ffffff",
          fontSize: "0.7rem",
          fontWeight: 700,
          fontStyle: "italic",
          lineHeight: "1.1rem",
          textAlign: "center",
          cursor: "pointer",
          padding: 0,
        }}
      >
        i
      </button>
      {open && (
        <span
          role="tooltip"
          style={{
            position: "absolute",
            zIndex: 50,
            left: "50%",
            top: "1.6rem",
            transform: "translateX(-50%)",
            width: "18rem",
            padding: "0.6rem 0.75rem",
            borderRadius: "0.5rem",
            border: "1px solid " + color.border,
            background: color.background,
            color: color.text,
            fontSize: "0.85rem",
            fontWeight: 400,
            fontStyle: "normal",
            lineHeight: 1.45,
            boxShadow: "0 4px 12px rgba(0, 0, 0, 0.08)",
          }}
        >
          {children}
        </span>
      )}
    </span>
  );
};
