def transform(data):
    # Distributes a fixed operator pool across production lines and derives the
    # number of shifts per line. Physical model: 1 operator = 1 shift of work.
    #   line capacity  = operators * work_days * output_per_op
    #   shifts         = ceil(operators / seats_per_shift)
    #   max operators  = seats_per_shift * max_shifts
    # Goal: level utilization (<=100%) without exceeding line capacity.
    # Method: greedy allocation + local-search correction (single-operator moves).

    data = data.copy()
    data["operators_assigned"] = 0
    data["shifts"] = 0
    data["monthly_output"] = 0
    data["utilization_pct"] = 0

    for period, idx in data.groupby("period").groups.items():
        grp = data.loc[idx]
        pool = int(grp["operator_pool"].iloc[0])

        work_days = grp["work_days"].astype(float).values
        out_op    = grp["output_per_op"].astype(float).values
        plan      = grp["prod_plan"].astype(float).values
        seats     = grp["seats_per_shift"].astype(int).values
        max_sh    = grp["max_shifts"].astype(int).values

        output_per_op = work_days * out_op
        capacity      = seats * max_sh
        n = len(grp)

        def utilization(ops):
            cap = np.where(ops > 0, ops * output_per_op, 1e-9)
            return np.where(plan > 0, plan / cap, -1.0)

        # phase 1: greedy allocation
        ops = np.zeros(n, dtype=int)
        for _ in range(pool):
            u = utilization(ops)
            u = np.where((plan > 0) & (ops < capacity), u, -np.inf)
            if np.all(~np.isfinite(u)):
                break
            ops[int(np.argmax(u))] += 1

        # phase 2: local-search correction
        def max_util(ops):
            u = utilization(ops)
            return np.max(np.where(u >= 0, u, 0))

        improved = True
        while improved:
            improved = False
            current = max_util(ops)
            for i in range(n):
                for j in range(n):
                    if i == j or ops[i] <= 0:
                        continue
                    if plan[j] <= 0 or ops[j] >= capacity[j]:
                        continue
                    if plan[i] > 0 and ops[i] - 1 == 0:
                        continue
                    test = ops.copy()
                    test[i] -= 1; test[j] += 1
                    if max_util(test) < current - 1e-9:
                        ops = test
                        improved = True
                        current = max_util(ops)

        # results
        shifts = np.where(ops > 0, np.ceil(ops / seats).astype(int), 0)
        cap = ops * output_per_op
        util = np.where(cap > 0, plan / cap, 0.0)

        data.loc[idx, "operators_assigned"] = ops
        data.loc[idx, "shifts"] = shifts
        data.loc[idx, "monthly_output"] = np.round(cap).astype(int)
        data.loc[idx, "utilization_pct"] = np.round(util * 100).astype(int)

    return data
