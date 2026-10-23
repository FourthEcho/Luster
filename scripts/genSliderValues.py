start          = float(input("start: "))
end            = float(input("end: "))
step           = float(input("step: "))
decimal_places = int(input("decimal places: "))

if step <= 0 or end < start:
    raise SystemExit("need step > 0 and end >= start")

# round() so float error (e.g. 0.7 / 0.1 = 6.999...) doesn't drop the last value
count = int(round((end - start) / step)) + 1

values = []
for i in range(count):
    value = round(i * step + start, decimal_places)
    if value == 0:
        value = 0.0  # avoid printing "-0.00"
    values.append(f"{value:.{decimal_places}f}")

print("[{0}]".format(" ".join(values)))
