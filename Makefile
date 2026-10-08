.PHONY: run dev test typecheck smoke app

run:
	bun run start

dev:
	bun run dev

test:
	bun test

typecheck:
	bun run typecheck

smoke:
	bun run smoke

app:
	./tray/build.sh
