def transform(data):
    """
    # Dodaje na dole komentarze żeby było wiadomo co sie dzieje
    """
    
    data = data.copy()
    data["oper_przydzielone"] = 0
    data["zmiany"] = 0
    data["wydajnosc_mies"] = 0
    data["oblozenie_proc"] = 0

    for miesiac, idx in data.groupby("data").groups.items():    # iteracja po wszystkich miesiacach
        grp = data.loc[idx]    # grp to wiersze danego miesiaca
        pula = int(grp["pula_operatorow"].iloc[0])   # pula to liczba operatorow do rozdania czyli 20

        dni   = grp["dni"].astype(float).values
        wyd   = grp["wyd_na_oper"].astype(float).values
        plan  = grp["plan_prod"].astype(float).values
        stan  = grp["stanowiska_zmiana"].astype(int).values
        zmax  = grp["zmiany_max"].astype(int).values

        moc_na_oper = dni * wyd                 # moc 1 operatora / miesiac
        pojemnosc   = stan * zmax               # max operatorow na linii, czyli maksymalna pojemnosc kazdej linii
        n = len(grp)

        def oblozenie(oper):                    # funkcja pomocnicza wykorzystywana niżej
            w = np.where(oper > 0, oper * moc_na_oper, 1e-9) # wydajnosc jako operator * moc na jednego operatora
            return np.where(plan > 0, plan / w, -1.0)        # zwraca obłożenie każdej linii czyli plan / wydajnosc, mikrowartosc ma chronić przed dzieleniem przez zero dla linii bez ludzi

        # --- faza 1: heurystyka ---
        oper = np.zeros(n, dtype=int)  
        for _ in range(pula):                          # petla w której rozdaje operatorów po jednym, w każdym obrocie: policz obłożenia, zablokuj linie bez planu i te już pełne, dodaj operatora tam gdzie najwieksze oblozenie
            obl = oblozenie(oper)
            obl = np.where((plan > 0) & (oper < pojemnosc), obl, -np.inf)
            if np.all(~np.isfinite(obl)):
                break                            
            oper[int(np.argmax(obl))] += 1

        # --- faza 2: korekta wsteczna ---
        def maks_obl(oper):                         # funkcja pomocniczna do operacji niżej, zwraca najgorsze/najwyższe obłożenie w danym rozkładzie
            o = oblozenie(oper)
            return np.max(np.where(o >= 0, o, 0))

        poprawiono = True
        while poprawiono:                           # przeniesienie jednego operatora z kazdej linii na kazdą inna i sprawdzenie czy to najwyższe oblożenie spadło, jesli przeniesienie pomogło to zostaje zatwierzdzone (ostatni if)
            poprawiono = False
            biezacy = maks_obl(oper)
            for i in range(n):          
                for j in range(n):      
                    if i == j or oper[i] <= 0:
                        continue
                    if plan[j] <= 0 or oper[j] >= pojemnosc[j]:
                        continue
                    if plan[i] > 0 and oper[i] - 1 == 0:
                        continue        
                    test = oper.copy()
                    test[i] -= 1; test[j] += 1
                    if maks_obl(test) < biezacy - 1e-9:
                        oper = test
                        poprawiono = True
                        biezacy = maks_obl(oper)

        # --- wyniki ---
        zmiany = np.where(oper > 0, np.ceil(oper / stan).astype(int), 0)
        w = oper * moc_na_oper
        obl = np.where(w > 0, plan / w, 0.0)

        data.loc[idx, "oper_przydzielone"] = oper
        data.loc[idx, "zmiany"] = zmiany
        data.loc[idx, "wydajnosc_mies"] = np.round(w).astype(int)
        data.loc[idx, "oblozenie_proc"] = np.round(obl * 100).astype(int)

    return data



