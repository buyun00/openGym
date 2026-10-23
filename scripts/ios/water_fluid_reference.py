"""Numerical reference for WaterFluid, for Windows diagnostics without Swift.

This is an independent Python port of the equations, NOT execution of the Swift
implementation. Keep its parameters/steps aligned when changing WaterPhysics.swift.
"""
import numpy as np


class Fluid:
    count = 64

    def __init__(self, fill=0.5, height=2.15):
        self.fill = min(1, max(0, fill))
        self.height = height
        self.h = np.full(self.count, self.fill * height)
        self.q = np.zeros(self.count)
        self.foam = np.zeros(self.count)

    @property
    def depths(self):
        return self.h / self.height

    @property
    def velocities(self):
        return np.divide(self.q, self.h, out=np.zeros(self.count), where=self.h > 1e-5)

    def conserve(self):
        self.h = np.clip(self.h, 0, self.height)
        difference = self.fill * self.height * self.count - self.h.sum()
        if abs(difference) > 1e-12:
            room = self.height - self.h if difference > 0 else self.h.copy()
            if room.sum() > 0:
                self.h += difference * room / room.sum()
        self.h = np.clip(self.h, 0, self.height)
        self.q = np.where(self.h < 1e-5, 0, np.clip(self.q, -2.4 * self.h, 2.4 * self.h))

    def disturb(self, position, amount):
        if self.fill <= 0 or self.fill >= 1:
            return
        x = (np.arange(self.count) + 0.5) / self.count
        bump = np.exp(-((x - np.clip(position, 0, 1)) ** 2) / 0.008)
        self.h += np.clip(amount, -0.08, 0.08) * self.height * (bump - bump.mean())
        self.conserve()

    def advance(self, dt, gx=0, gy=1, ax=0, ay=0):
        if self.fill <= 0 or self.fill >= 1:
            return
        gravity = 0.9 * min(2, max(0.25, abs(gy) - ay * 0.6))
        force = 0.9 * np.clip(gx - ax * 1.35, -2.4, 2.4)
        dx = 1 / self.count
        remaining = min(dt, 0.1)
        while remaining > 1e-9:
            speed = max(0.01, np.max(np.abs(self.velocities) + np.sqrt(gravity * self.h)))
            step = min(remaining, 1 / 120, 0.42 * dx / (speed + abs(force) / 120))
            self.q += self.h * force * step * 0.5
            left_h = np.r_[self.h[0], self.h]
            right_h = np.r_[self.h, self.h[-1]]
            left_q = np.r_[-self.q[0], self.q]
            right_q = np.r_[self.q, -self.q[-1]]
            left_v = np.divide(left_q, left_h, out=np.zeros(self.count + 1), where=left_h > 1e-5)
            right_v = np.divide(right_q, right_h, out=np.zeros(self.count + 1), where=right_h > 1e-5)
            signal = np.maximum(np.abs(left_v) + np.sqrt(gravity * left_h),
                                np.abs(right_v) + np.sqrt(gravity * right_h))
            mass_flux = (left_q + right_q - signal * (right_h - left_h)) * 0.5
            momentum_flux = (left_q * left_v + right_q * right_v
                             + 0.5 * gravity * (left_h ** 2 + right_h ** 2)
                             - signal * (right_q - left_q)) * 0.5
            self.h -= step / dx * np.diff(mass_flux)
            self.q -= step / dx * np.diff(momentum_flux)
            self.q = (self.q + np.maximum(0, self.h) * force * step * 0.5) * np.exp(-0.95 * step)
            hit_top = self.h > self.height
            self.foam = np.where(hit_top, np.minimum(1, self.foam + (self.h - self.height) * 8), self.foam)
            self.q = np.where(hit_top, self.q * 0.35, self.q)
            self.conserve()
            remaining -= step
        velocity = self.velocities
        left = np.r_[-velocity[0], velocity[:-1]]
        right = np.r_[velocity[1:], -velocity[-1]]
        compression = np.maximum(0, (left - right) / (2 * dx) - 0.4)
        self.foam = np.minimum(1, self.foam * np.exp(-2.2 * min(dt, 0.1)) + compression * min(dt, 0.1) * 0.16)


def check_reference():
    max_volume_error = 0
    for fill in [0, 0.005, 0.25, 0.5, 0.75, 0.995, 1]:
        fluid = Fluid(fill)
        for i in range(120):
            fluid.advance(1 / 30, gx=0.6 * np.sin(i * 0.2), ax=1.2 * np.sin(i * 0.3))
            max_volume_error = max(max_volume_error, abs(fluid.depths.mean() - fill))
            assert np.isfinite(fluid.h).all() and np.isfinite(fluid.q).all()
            assert fluid.depths.min() >= 0 and fluid.depths.max() <= 1
    assert max_volume_error < 1e-10
    fluid = Fluid()
    for _ in range(4):
        fluid.advance(1 / 30, ax=-1)
    x = (np.arange(fluid.count) + 0.5) / fluid.count
    residual = float(np.sqrt(np.mean((fluid.depths - np.polyval(np.polyfit(x, fluid.depths, 1), x)) ** 2)))
    assert residual > 0.001, "An accelerated surface must curve, not remain a pivoted line"
    first = fluid.depths.copy()
    for _ in range(20):
        fluid.advance(1 / 30)
    assert np.max(np.abs(first - fluid.depths)) > 0.01
    peak = float(np.max(np.abs(fluid.depths - 0.5)))
    for _ in range(300):
        fluid.advance(1 / 30)
    settled = float(np.max(np.abs(fluid.depths - 0.5)))
    assert settled < max(0.001, peak * 0.05)
    # Equal physical time at different display rates uses the same CFL bound.
    outcomes = []
    for fps in [15, 30, 60]:
        fluid = Fluid()
        for _ in range(fps):
            fluid.advance(1 / fps, ax=-0.6)
        outcomes.append(fluid.depths.copy())
    frame_rate_error = float(np.max(np.abs(outcomes[0] - outcomes[-1])))
    assert frame_rate_error < 0.004
    return {"scope": "Python reference equations only; Swift tests are not executed",
            "max_volume_error": float(max_volume_error), "curved_surface_rms": residual,
            "settled_amplitude": settled, "frame_rate_max_difference": frame_rate_error}


if __name__ == "__main__":
    import json
    print(json.dumps(check_reference(), indent=2))
