"""The skills in the Electric motors sample: a 3D motor, a widget, a diorama, a simulation.

Hand-made showcase content (a dev/test fixture, never shipped as a notebook).
`T(en, da)` makes a bilingual string; motors.py picks the language.
"""
import math


def skills(T):
    return motor_model(T), force_widget(T), wind_farm(T), winch_sim(T)


def winch_sim(T):
    """A motor winching a load up on a rope: pull against weight, live, with a plot of the height."""
    return dict(kind="sim", spec=dict(
        view=[-2, 0, 2, 4], gravity=[0, -9.81], floor=True,
        params=dict(
            pull=dict(value=14, min=0, max=30, step=0.5, label=T("Motor pull", "Motorens træk"), unit="N"),
            m=dict(value=1, min=0.2, max=2.5, step=0.1, label=T("Load", "Last"), unit="kg")),
        bodies=[
            dict(id="drum", shape="circle", r=0.18, x=0, y=3.7, fixed=True, color="black", label=T("Motor", "Motor")),
            dict(id="load", shape="box", w=0.5, h=0.4, x=0, y=0.2, mass="m", color="accent", label=T("Load", "Last"), bounce=0.1)],
        links=[dict(type="rope", a="drum", b="load")],
        # The motor pulls until the load nears the top, then holds it there (brake: weight plus damping).
        forces=[dict(on="load", fx="0", fy="load_y < 2.4 ? pull : m*9.81 - 12*load_vy")],
        readouts=[
            dict(label=T("Net force", "Nettokraft"), expr="pull - m*9.81", unit="N", digits=1),
            dict(label=T("Speed", "Fart"), expr="load_vy", unit="m/s", digits=2)],
        plot=[dict(expr="load_y", label=T("Height", "Højde"), unit="m")],
        caption=T("Pull more than the weight (m × 9.81 N) and the load rises, faster and faster.",
                  "Træk mere end vægten (m × 9,81 N), og lasten stiger, hurtigere og hurtigere.")))


def motor_model(T):
    """A brushless outrunner: the stator and coils stand still; the bell, magnets and
    shaft spin together as one group. Every part explains itself; Explode opens it up."""
    parts = [dict(shape="cylinder", radius=0.5, height=0.9, position=[0, 0, 0], color="grey",
                  label=T("Stator", "Stator"),
                  detail=T("The still core. Its coils become magnets when current flows.",
                           "Den stille kerne. Dens spoler bliver magneter, når strømmen løber."))]
    for k in range(6):
        a = math.radians(k * 60)
        coil = dict(shape="box", size=[0.42, 0.7, 0.34], position=[round(0.95 * math.cos(a), 3), 0, round(0.95 * math.sin(a), 3)],
                    rotation=[0, -k * 60, 0], color="dark", explode=[round(0.55 * math.cos(a), 2), 0, round(0.55 * math.sin(a), 2)])
        if k == 0:
            coil.update(label=T("Coil", "Spole"), detail=T("Copper wire wound round an iron tooth. Switched on, it pulls the nearest magnet.",
                                                           "Kobbertråd viklet om en jerntand. Tændt trækker den i den nærmeste magnet."))
        parts.append(coil)
    parts.append(dict(shape="ring", radius=1.55, inner=1.4, height=0.95, position=[0, 0, 0], color="glass", group="rotor", explode=[0, 1.7, 0],
                      label=T("Bell", "Klokke"), detail=T("The outer shell that spins. Propellers bolt to it.",
                                                          "Den ydre skal, der drejer. Propellerne skrues fast på den.")))
    for k in range(8):
        a = math.radians(k * 45 + 22.5)
        magnet = dict(shape="box", size=[0.12, 0.8, 0.3], position=[round(1.33 * math.cos(a), 3), 0, round(1.33 * math.sin(a), 3)],
                      rotation=[0, -(k * 45 + 22.5), 0], color="accent", group="rotor", explode=[0, 1.7, 0])
        if k == 1:
            magnet.update(label=T("Magnet", "Magnet"), detail=T("Permanent magnets, alternating north and south, glued inside the bell.",
                                                                "Permanente magneter, skiftevis nord og syd, limet inde i klokken."))
        parts.append(magnet)
    parts.append(dict(shape="cylinder", radius=0.08, height=2.6, position=[0, 0.6, 0], color="black", group="rotor", explode=[0, 2.6, 0],
                      label=T("Shaft", "Aksel"), detail=T("Carries the turning force out of the motor.", "Fører den drejende kraft ud af motoren.")))
    parts.append(dict(shape="cylinder", radius=1.2, height=0.12, position=[0, -0.6, 0], color="light", explode=[0, -0.7, 0],
                      label=T("Mount", "Beslag"), detail=T("Screws the stator to the drone arm. It never turns.",
                                                           "Skruer statoren fast på dronens arm. Den drejer aldrig.")))
    return dict(kind="model3d", spec=dict(
        parts=parts,
        groups=dict(rotor=dict(pivot=[0, 0, 0], spin=dict(axis="y", rpm=20))),
        camera=dict(azimuth=30, elevation=28),
        caption=T("Drag to turn · tap a part · Explode to look inside", "Træk for at dreje · tryk på en del · Eksplodér for at se indeni")))


def force_widget(T):
    """F = B·I·L, live: three sliders, a readout, a meter, a plot, a quiz, a sum to work out."""
    return dict(kind="ui", spec=dict(state=dict(B=0.5, I=2, L=0.1), blocks=[
        dict(type="heading", text="F = B · I · L"),
        dict(type="text", text=T("A wire carrying current in a magnetic field gets pushed. Change each part and watch the push.",
                                 "En ledning med strøm i et magnetfelt bliver skubbet. Skift hver del, og se skubbet.")),
        dict(type="row", blocks=[
            dict(type="slider", var="B", min=0, max=1.5, step=0.05, label=T("Field B", "Felt B"), unit="T"),
            dict(type="slider", var="I", min=0, max=10, step=0.1, label=T("Current I", "Strøm I"), unit="A"),
            dict(type="slider", var="L", min=0.01, max=0.3, step=0.01, label=T("Length L", "Længde L"), unit="m")]),
        dict(type="row", blocks=[
            dict(type="readout", label=T("Force", "Kraft"), expr="B*I*L", unit="N", digits=3),
            dict(type="meter", label=T("of the strongest push here", "af det største skub her"), expr="B*I*L", max=4.5, unit="N")]),
        dict(type="plot", label=T("Force as the current rises", "Kraften når strømmen stiger"), expr="B*x*L", xmin=0, xmax=10,
             xLabel=T("current, A", "strøm, A"), marker="I"),
        dict(type="quiz", question=T("Double the current. The force…", "Fordobl strømmen. Kraften…"),
             options=[T("halves", "halveres"), T("stays the same", "er den samme"), T("doubles", "fordobles"), T("quadruples", "firdobles")],
             answer=2, explain=T("F is proportional to I: twice the current, twice the push.", "F er proportional med I: dobbelt strøm, dobbelt skub.")),
        dict(type="answer", question=T("B = 0.8 T, I = 5 A, L = 0.2 m. What is F?", "B = 0,8 T, I = 5 A, L = 0,2 m. Hvad er F?"),
             answer="0.8*5*0.2", unit="N", hint=T("Multiply all three.", "Gang alle tre."),
             explain=T("0.8 × 5 × 0.2 = 0.8 N.", "0,8 × 5 × 0,2 = 0,8 N.")),
    ]))


def wind_farm(T):
    """Turbines are motors run backwards. Three steps: wind, generator, grid."""
    return dict(kind="diorama", spec=dict(
        layers=[
            dict(depth=0.05, items=[dict(shape="rect", x=0, y=0, w=100, h=60, fill="sky"),
                                    dict(prop="sun", x=84, y=18, s=1.1),
                                    dict(prop="cloud", x=20, y=12, s=1.3, fill="white", anim="drift"),
                                    dict(prop="cloud", x=58, y=8, s=0.9, fill="white", anim="drift")]),
            dict(depth=0.25, items=[dict(shape="rect", x=-10, y=43, w=120, h=20, fill="green"),
                                    dict(prop="hill", x=18, y=44, s=2.2), dict(prop="hill", x=72, y=42, s=2.6),
                                    dict(prop="pine", x=8, y=44, s=0.8), dict(prop="pine", x=12, y=45, s=0.6)]),
            dict(depth=0.55, items=[dict(prop="turbine", x=30, y=48, s=1.6, fill="white"),
                                    dict(prop="turbine", x=56, y=46, s=1.25, fill="white"),
                                    dict(prop="turbine", x=78, y=45, s=1.0, fill="white"),
                                    dict(shape="path", d="M30 48 L13 51 M56 46 L13 51 M78 45 L13 51", fill="none", stroke="accent", strokeWidth=0.4, step=3)]),
            dict(depth=0.9, items=[dict(shape="path", d="M0 52 C 25 47, 55 55, 100 49 L100 60 L0 60 Z", fill="grey"),
                                   dict(prop="factory", x=12, y=54, s=0.8, step=3),
                                   dict(prop="house", x=88, y=52, s=0.8)]),
        ],
        steps=[dict(label=T("Wind pushes the blades", "Vinden skubber vingerne")),
               dict(label=T("The generator turns motion into current", "Generatoren gør bevægelse til strøm")),
               dict(label=T("Power travels to the grid", "Strømmen sendes ud på nettet"))],
        hotspots=[
            dict(x=22, y=16, step=1, label=T("Blades", "Vinger"),
                 detail=T("Shaped like wings: the wind makes lift that turns them about 15 times a minute.",
                          "Formet som vinger: vinden giver opdrift, der drejer dem cirka 15 gange i minuttet.")),
            dict(x=31, y=25, step=2, label=T("Generator", "Generator"),
                 detail=T("A motor run backwards: magnets sweep past coils and push current out.",
                          "En motor kørt baglæns: magneter fejer forbi spoler og skubber strøm ud.")),
            dict(x=12, y=42, step=3, label=T("Substation", "Transformerstation"),
                 detail=T("Raises the voltage so the power can travel far with little loss.",
                          "Hæver spændingen, så strømmen kan rejse langt med lille tab.")),
        ],
        caption=T("Drag to look around · step through · tap the dots", "Træk for at se dig om · gå trin for trin · tryk på prikkerne")))
