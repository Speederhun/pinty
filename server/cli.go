package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

const usage = `Pinty szerver

Használat:
  pinty-server                           a szerver indítása
  pinty-server invite <e-mail> [napok]   egyszer használható meghívókód készítése (alap: 7 nap)
  pinty-server invites                   a meghívók listája
  pinty-server revoke <e-mail>           az e-mailhez tartozó, még fel nem használt meghívók törlése

A parancsok a PINTY_DATA könyvtár adatbázisát használják. Futtasd őket ugyanazzal a
felhasználóval, mint a szolgáltatást, például:
  sudo -u pinty env PINTY_DATA=/var/lib/pinty /opt/pinty/pinty-server invite valaki@example.com
`

func runCLI(args []string) int {
	switch args[0] {
	case "invite":
		return cmdInvite(args[1:])
	case "invites":
		return cmdInvites()
	case "revoke":
		return cmdRevoke(args[1:])
	case "help", "-h", "--help":
		fmt.Print(usage)
		return 0
	default:
		fmt.Fprintf(os.Stderr, "ismeretlen parancs: %s\n\n%s", args[0], usage)
		return 2
	}
}

// openCLIStore a meglévő adatbázist nyitja meg; hibás PINTY_DATA esetén nem hoz létre újat.
func openCLIStore() (*store, error) {
	path := filepath.Join(env("PINTY_DATA", "./data"), "pinty.db")
	if _, err := os.Stat(path); err != nil {
		return nil, fmt.Errorf("nem találom az adatbázist: %s (állítsd be a PINTY_DATA-t)", path)
	}
	return openStore(path)
}

func cmdInvite(args []string) int {
	if len(args) < 1 || len(args) > 2 {
		fmt.Fprint(os.Stderr, usage)
		return 2
	}
	email := normEmail(args[0])
	if !emailRe.MatchString(email) {
		fmt.Fprintln(os.Stderr, "érvénytelen e-mail cím")
		return 2
	}
	days := 7
	if len(args) == 2 {
		n, err := strconv.Atoi(args[1])
		if err != nil || n < 1 || n > 90 {
			fmt.Fprintln(os.Stderr, "a napok száma 1 és 90 között legyen")
			return 2
		}
		days = n
	}
	st, err := openCLIStore()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	defer st.Close()

	if _, err := st.userByEmail(email); err == nil {
		fmt.Fprintln(os.Stderr, "ehhez az e-mail címhez már tartozik fiók")
		return 1
	}
	code, hash, err := newInviteCode()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	exp := time.Now().Add(time.Duration(days) * 24 * time.Hour)
	if err := st.createInvite(email, hash, exp); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	fmt.Printf("Meghívó: %s\nE-mail:  %s\nÉrvényes: %d napig (%s-ig), egyszer használható.\n",
		code, email, days, exp.Format("2006-01-02 15:04"))
	return 0
}

func cmdInvites() int {
	st, err := openCLIStore()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	defer st.Close()
	list, err := st.listInvites()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if len(list) == 0 {
		fmt.Println("Nincs meghívó.")
		return 0
	}
	now := time.Now().Unix()
	for _, iv := range list {
		state := "függőben"
		switch {
		case iv.UsedAt != 0:
			state = "felhasználva"
		case iv.ExpiresAt < now:
			state = "lejárt"
		}
		fmt.Printf("%-40s %-13s lejár: %s\n", iv.Email, state, time.Unix(iv.ExpiresAt, 0).Format("2006-01-02 15:04"))
	}
	return 0
}

func cmdRevoke(args []string) int {
	if len(args) != 1 {
		fmt.Fprint(os.Stderr, usage)
		return 2
	}
	st, err := openCLIStore()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	defer st.Close()
	n, err := st.revokeInvites(normEmail(args[0]))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	fmt.Printf("%d meghívó törölve.\n", n)
	return 0
}
